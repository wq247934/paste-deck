import Foundation

/// The WebSocket transport over `URLSessionWebSocketTask` (METRICS 11.9, Connection): an ephemeral session without
/// cookies, credentials or cache, no authentication challenge answered (server trust only), no redirect followed,
/// TLS 1.2 or later, `wss` (or `ws` to loopback only), the subprotocol required in the `101`, a Ping every
/// `pingIntervalSeconds` and an abort when its Pong takes longer than `pongTimeoutSeconds`.
public struct URLSessionReportStream: ReportStreamTransport {
    public init() {}

    public func link(
        settings: ReportStreamSettings, queue: DispatchQueue,
        onEvent: @escaping @Sendable (ReportStreamEvent) -> Void,
        onSigningFailure: @escaping @Sendable () -> Void
    ) -> any ReportStreamLink {
        URLSessionReportStreamLink(settings: settings, queue: queue, onEvent: onEvent, onSigningFailure: onSigningFailure)
    }
}

/// One connection. Its mutable state is guarded by `lock`; signing, writes and Pings run in order on `work`, and
/// events reach the owner on `queue`, never after the owner closed or aborted the link.
final class URLSessionReportStreamLink: NSObject, ReportStreamLink, URLSessionWebSocketDelegate, @unchecked Sendable {
    static let handshakeTimeout: TimeInterval = 10
    private static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]

    private let settings: ReportStreamSettings
    private let queue: DispatchQueue
    private let onEvent: @Sendable (ReportStreamEvent) -> Void
    private let onSigningFailure: @Sendable () -> Void
    private let work = DispatchQueue(label: "io.github.zoefix.agentspeed.report.stream")
    private let delegateQueue = OperationQueue()
    private let lock = NSLock()
    private var ended = false
    private var silenced = false
    private var opened = false
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var pingTimer: DispatchSourceTimer?
    private var pingToken = 0
    private var awaitingPong: Int?

    init(settings: ReportStreamSettings, queue: DispatchQueue, onEvent: @escaping @Sendable (ReportStreamEvent) -> Void,
         onSigningFailure: @escaping @Sendable () -> Void) {
        self.settings = settings
        self.queue = queue
        self.onEvent = onEvent
        self.onSigningFailure = onSigningFailure
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = work
        delegateQueue.name = "io.github.zoefix.agentspeed.report.stream.delegate"
    }

    // MARK: - ReportStreamLink

    func start(_ makeRequest: @escaping @Sendable () throws -> ReportRequest) {
        work.async { [self] in
            guard !isEnded else { return }
            guard let request = try? makeRequest() else {
                signingFailed()
                return
            }
            guard Self.isAllowed(request.url) else {
                finish(.closed(code: 1002))
                return
            }
            var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                        timeoutInterval: Self.handshakeTimeout)
            urlRequest.httpShouldHandleCookies = false
            // CFNetwork would add the user's languages; a constant says nothing about the user (REPORTING 1.3).
            urlRequest.setValue("*", forHTTPHeaderField: "Accept-Language")
            for header in request.headers { urlRequest.setValue(header.value, forHTTPHeaderField: header.name) }
            let session = URLSession(configuration: Self.configuration, delegate: self, delegateQueue: delegateQueue)
            let task = session.webSocketTask(with: urlRequest)
            task.maximumMessageSize = settings.maxMessageBytes
            lock.withLock {
                self.session = session
                self.task = task
            }
            task.resume()
        }
    }

    func send(_ makeText: @escaping @Sendable () throws -> String) {
        work.async { [self] in
            guard !isEnded, let task = lock.withLock({ self.task }) else { return }
            guard let text = try? makeText() else {
                signingFailed()
                return
            }
            task.send(.string(text)) { [weak self] error in
                guard error != nil, let self else { return }
                work.async { self.finish(.closed(code: 1006)) }
            }
        }
    }

    func close() {
        end(silently: true) { task, session in
            task?.cancel(with: .normalClosure, reason: nil)
            session?.finishTasksAndInvalidate()
        }
    }

    func abort() {
        end(silently: true) { task, session in
            task?.cancel()
            session?.invalidateAndCancel()
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol chosen: String?) {
        let response = webSocketTask.response as? HTTPURLResponse
        let extensions = response?.value(forHTTPHeaderField: "Sec-WebSocket-Extensions")?
            .trimmingCharacters(in: .whitespaces) ?? ""
        // URLSession offers permessage-deflate on its own; a service that selects it breaks the protocol.
        guard chosen == ReportStreamSettings.subprotocol, extensions.isEmpty else {
            finish(.closed(code: 1002))
            return
        }
        guard lock.withLock({ () -> Bool in
            guard !ended else { return false }
            opened = true
            return true
        }) else { return }
        deliver(.opened)
        receive(webSocketTask)
        startPings()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(.closed(code: closeCode.rawValue))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let wasOpened = lock.withLock { opened }
        guard wasOpened else {
            if let response = task.response as? HTTPURLResponse, response.statusCode != 101 {
                finish(.rejected(status: response.statusCode,
                                 retryAfter: response.value(forHTTPHeaderField: "Retry-After")))
            } else {
                finish(.closed(code: 1006))
            }
            return
        }
        let closeCode = (task as? URLSessionWebSocketTask)?.closeCode ?? .invalid
        if closeCode != .invalid {
            finish(.closed(code: closeCode.rawValue))
        } else if let error = error as NSError?, error.domain == NSPOSIXErrorDomain, error.code == Int(EMSGSIZE) {
            finish(.closed(code: 1002))
        } else {
            finish(.closed(code: 1006))
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Steps

    private static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = [:]
        config.timeoutIntervalForRequest = handshakeTimeout
        config.waitsForConnectivity = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return config
    }

    /// `wss`, or `ws` to a loopback host (the test service of REPORTING 2.2).
    static func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "wss": return url.host != nil
        case "ws": return url.host.map { loopbackHosts.contains($0.lowercased()) } ?? false
        default: return false
        }
    }

    private var isEnded: Bool { lock.withLock { ended } }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                guard let message = ReportServiceMessage.parse(Data(text.utf8), maxBytes: settings.maxMessageBytes) else {
                    finish(.closed(code: 1002))
                    return
                }
                if message != .other { deliver(.message(message)) }
                receive(task)
            case .success:
                finish(.closed(code: 1002))
            case .failure:
                // didCloseWith or didCompleteWithError reports how the connection ended.
                break
            }
        }
    }

    private func startPings() {
        let timer = DispatchSource.makeTimerSource(queue: work)
        let interval = DispatchTimeInterval.seconds(settings.pingIntervalSeconds)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.ping() }
        let started = lock.withLock { () -> Bool in
            guard !ended else { return false }
            pingTimer = timer
            return true
        }
        if started { timer.resume() }
    }

    private func ping() {
        let state = lock.withLock { () -> (URLSessionWebSocketTask, Int)? in
            guard !ended, let task, awaitingPong == nil else { return nil }
            pingToken += 1
            awaitingPong = pingToken
            return (task, pingToken)
        }
        guard let (task, token) = state else { return }
        task.sendPing { [weak self] error in
            guard error == nil, let self else { return }
            work.async { self.ponged(token) }
        }
        work.asyncAfter(deadline: .now() + .seconds(settings.pongTimeoutSeconds)) { [weak self] in
            guard let self, lock.withLock({ awaitingPong == token }) else { return }
            finish(.closed(code: 1006))
        }
    }

    private func ponged(_ token: Int) {
        lock.withLock { if awaitingPong == token { awaitingPong = nil } }
    }

    private func signingFailed() {
        end(silently: true) { task, session in
            task?.cancel()
            session?.invalidateAndCancel()
        }
        let onSigningFailure = onSigningFailure
        queue.async { onSigningFailure() }
    }

    /// The connection ended on its own (or broke the protocol): the last event, then nothing more.
    private func finish(_ event: ReportStreamEvent) {
        var report = false
        end(silently: false) { task, session in
            report = true
            task?.cancel()
            session?.invalidateAndCancel()
        }
        if report { deliver(event, final: true) }
    }

    private func end(silently: Bool, _ release: (URLSessionWebSocketTask?, URLSession?) -> Void) {
        let state = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, DispatchSourceTimer?)? in
            if silently { silenced = true }
            guard !ended else { return nil }
            ended = true
            defer {
                task = nil
                session = nil
                pingTimer = nil
                awaitingPong = nil
            }
            return (task, session, pingTimer)
        }
        guard let (task, session, timer) = state else { return }
        timer?.cancel()
        release(task, session)
    }

    /// Events are queued in the order they happen on `work`; the owner's close or abort silences the rest.
    private func deliver(_ event: ReportStreamEvent, final: Bool = false) {
        guard final || !isEnded else { return }
        queue.async { [self] in
            if !lock.withLock({ silenced }) { onEvent(event) }
        }
    }
}
