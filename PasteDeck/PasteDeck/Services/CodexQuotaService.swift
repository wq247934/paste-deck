//
//  CodexQuotaService.swift
//  PasteDeck
//
//  查询本机 Codex / ChatGPT 桌面版的剩余额度：拉起内置 codex CLI 的
//  app-server JSON-RPC（stdio），读取速率限制快照。
//  逻辑与 codex-quota-utools 插件的 quota.js 保持一致。
//
//  Created on 2026-10-11.
//

import Foundation

enum CodexQuotaService {

    static let sessionWindowLabel = "5 小时额度"
    static let weeklyWindowLabel = "每周额度"

    private static let queryTimeout: TimeInterval = 15

    enum CodexQuotaError: LocalizedError {
        case cliNotFound
        case timeout
        case launchFailed(String)
        case exitedWithoutData(exitCode: Int32)
        case rpcError(String)
        case noRateLimits

        var errorDescription: String? {
            switch self {
            case .cliNotFound:
                return "未检测到 ChatGPT / Codex 应用，请确认已安装 ChatGPT 桌面版且已登录"
            case .timeout:
                return "查询超时（15 秒无响应），请确认 ChatGPT / Codex 已安装且已登录"
            case .launchFailed(let message):
                return "应用启动失败：\(message)。请确认已安装且已登录"
            case .exitedWithoutData(let exitCode):
                return "应用进程已退出（code=\(exitCode)），未返回额度数据。请确认已安装且已登录"
            case .rpcError(let message):
                return "Codex 返回错误：\(message)"
            case .noRateLimits:
                return "无速率限制数据"
            }
        }
    }

    // MARK: - 数据模型

    /// 单个额度窗口；isAvailable 为 false 表示当前无此窗口（如 5 小时额度暂未分配）。
    struct Window: Equatable {
        var label: String
        var isAvailable: Bool
        var usedPercent: Double
        var remainingPercent: Double
        var windowMinutes: Int?
        var resetsAt: Date?
    }

    struct ResetCredit: Equatable {
        var title: String?
        var status: String?
        var expiresAt: Date?
        var grantedAt: Date?
    }

    struct Snapshot: Equatable {
        var plan: String?
        var limitName: String?
        var isRateLimitReached: Bool
        /// primary 窗口，即 5 小时额度。
        var session: Window
        /// secondary 窗口，即每周额度。
        var weekly: Window
        var availableCredits: Int?
        var resetCreditsAvailableCount: Int?
        var resetCredits: [ResetCredit]
    }

    // MARK: - 查询入口

    static func query() async throws -> Snapshot {
        let codexPath = resolveCodexPath()
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            throw CodexQuotaError.cliNotFound
        }
        return try await runSession(codexPath: codexPath)
    }

    /// 2026-09 起新版 ChatGPT.app 把内置 codex 移到了 Resources/codex-cli/ 下；兼容旧版 Codex.app。
    static func resolveCodexPath() -> String {
        if let override = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"], !override.isEmpty {
            return override
        }
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }

    // MARK: - JSON-RPC 会话

    private static func runSession(codexPath: String) async throws -> Snapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = environment["CODEX_HOME"]
            ?? NSHomeDirectory().appending("/.codex")
        process.environment = environment
        process.standardError = FileHandle.nullDevice

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        do {
            try process.run()
        } catch {
            throw CodexQuotaError.launchFailed(error.localizedDescription)
        }

        return try await withThrowingTaskGroup(of: Snapshot.self) { group -> Snapshot in
            let session = SessionReader(process: process, input: inputPipe, output: outputPipe)

            group.addTask {
                try await session.run()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(queryTimeout * 1_000_000_000))
                throw CodexQuotaError.timeout
            }

            let firstResult: Result<Snapshot, Error>
            do {
                firstResult = .success(try await group.next()!)
            } catch {
                firstResult = .failure(error)
            }

            // 无论谁先完成，都要结束子进程并唤醒仍在挂起的会话任务。
            session.stop()
            group.cancelAll()
            while (try? await group.next()) != nil {}

            return try firstResult.get()
        }
    }

    /// 读取 app-server 的 stdout 行并驱动 initialize → rateLimits 两次请求。
    /// 会从多个线程回调（readabilityHandler、terminationHandler、任务组），全部经锁串行化。
    private final class SessionReader: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Snapshot, Error>?
        private var buffer = Data()
        private var nextRequestID = 1
        private var isFinished = false

        private let process: Process
        private let inputPipe: Pipe
        private let outputPipe: Pipe

        init(process: Process, input: Pipe, output: Pipe) {
            self.process = process
            self.inputPipe = input
            self.outputPipe = output
        }

        func run() async throws -> Snapshot {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    self?.consumeOutput(handle.availableData)
                }
                process.terminationHandler = { [weak self] terminatedProcess in
                    self?.handleProcessTermination(exitCode: terminatedProcess.terminationStatus)
                }

                send(
                    method: "initialize",
                    params: [
                        "clientInfo": [
                            "name": "PasteDeck",
                            "title": "PasteDeck",
                            "version": "1.0.0",
                        ],
                        "capabilities": NSNull(),
                    ]
                )
            }
        }

        /// 结束会话：杀掉子进程，并把仍在挂起的 continuation 以超时错误唤醒。
        func stop() {
            finish(with: .failure(CodexQuotaError.timeout))
        }

        private func consumeOutput(_ data: Data) {
            guard !data.isEmpty else {
                handleProcessTermination(exitCode: process.terminationStatus)
                return
            }

            lock.lock()
            buffer.append(data)
            var lines: [Data] = []
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newlineIndex]
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                lines.append(Data(line))
            }
            lock.unlock()

            for line in lines {
                handleLine(line)
            }
        }

        private func handleLine(_ line: Data) {
            let trimmed = line.trimmingJSONWhitespace()
            guard !trimmed.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: trimmed) as? [String: Any],
                  let identifier = (message["id"] as? NSNumber)?.intValue else {
                return
            }

            // initialize 响应到达后再发送 rateLimits 请求
            if identifier == 1 {
                send(method: "account/rateLimits/read")
                return
            }
            guard identifier == 2 else { return }

            if let rpcError = message["error"] as? [String: Any] {
                let text = rpcError["message"] as? String
                    ?? (try? String(data: JSONSerialization.data(withJSONObject: rpcError), encoding: .utf8))
                    ?? "未知错误"
                finish(with: .failure(CodexQuotaError.rpcError(text)))
                return
            }

            let rpcResult = message["result"] as? [String: Any] ?? [:]
            do {
                finish(with: .success(try CodexQuotaService.parseSnapshot(rpcResult: rpcResult)))
            } catch {
                finish(with: .failure(error))
            }
        }

        private func handleProcessTermination(exitCode: Int32) {
            lock.lock()
            let leftover = buffer
            buffer = Data()
            lock.unlock()

            if !leftover.isEmpty {
                handleLine(leftover)
            }
            finish(with: .failure(CodexQuotaError.exitedWithoutData(exitCode: exitCode)))
        }

        /// 唯一的完成出口：清理管道与子进程，且只 resume 一次。
        private func finish(with result: Result<Snapshot, Error>) {
            lock.lock()
            if isFinished {
                lock.unlock()
                return
            }
            isFinished = true
            let pendingContinuation = continuation
            continuation = nil
            lock.unlock()

            outputPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
            }

            switch result {
            case .success(let snapshot):
                pendingContinuation?.resume(returning: snapshot)
            case .failure(let error):
                pendingContinuation?.resume(throwing: error)
            }
        }

        // MARK: - 请求发送

        private func send(method: String, params: [String: Any]? = nil) {
            var payload: [String: Any] = ["id": nextRequestID, "method": method]
            if let params {
                payload["params"] = params
            }
            nextRequestID += 1

            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
            try? inputPipe.fileHandleForWriting.write(contentsOf: data + Data([UInt8(ascii: "\n")]))
        }
    }

    // MARK: - 快照解析

    /// 从 rateLimits 响应的 result 字段解析展示快照；与 quota.js formatQuota 对齐。
    static func parseSnapshot(rpcResult: [String: Any]) throws -> Snapshot {
        let byLimitID = rpcResult["rateLimitsByLimitId"] as? [String: Any]
        guard let snapshot = (byLimitID?["codex"] ?? rpcResult["rateLimits"] ?? byLimitID?.values.first)
            as? [String: Any] else {
            throw CodexQuotaError.noRateLimits
        }

        let primary = buildWindow(raw: snapshot["primary"], label: sessionWindowLabel)
        let secondary = buildWindow(raw: snapshot["secondary"], label: weeklyWindowLabel)

        let reachedType = Self.string(snapshot["rateLimitReachedType"]) ?? ""
        let credits = snapshot["credits"] as? [String: Any]

        let resetCreditsRaw = rpcResult["rateLimitResetCredits"] as? [String: Any]
        let resetCreditList: [ResetCredit] = ((resetCreditsRaw?["credits"] as? [[String: Any]]) ?? [])
            .map(Self.parseResetCredit)
            .sorted { lhs, rhs in
                switch (lhs.expiresAt, rhs.expiresAt) {
                case let (lhsDate?, rhsDate?): return lhsDate < rhsDate
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return false
                }
            }

        return Snapshot(
            plan: Self.string(snapshot["planType"]),
            limitName: Self.string(snapshot["limitName"]),
            isRateLimitReached: !reachedType.isEmpty,
            session: primary,
            weekly: secondary,
            availableCredits: credits.flatMap { Self.int($0["availableCount"]) },
            resetCreditsAvailableCount: resetCreditsRaw.flatMap { Self.int($0["availableCount"]) },
            resetCredits: resetCreditList
        )
    }

    private static func buildWindow(raw: Any?, label: String) -> Window {
        guard let window = raw as? [String: Any], !window.isEmpty else {
            return Window(
                label: label,
                isAvailable: false,
                usedPercent: 0,
                remainingPercent: 100,
                windowMinutes: nil,
                resetsAt: nil
            )
        }

        let used = Self.double(window["usedPercent"]) ?? 0
        return Window(
            label: label,
            isAvailable: true,
            usedPercent: used,
            remainingPercent: max(0, 100 - used),
            windowMinutes: Self.int(window["windowDurationMins"]),
            resetsAt: Self.double(window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func parseResetCredit(_ raw: [String: Any]) -> ResetCredit {
        ResetCredit(
            title: string(raw["title"]),
            status: string(raw["status"]),
            expiresAt: double(raw["expiresAt"]).map { Date(timeIntervalSince1970: $0) },
            grantedAt: double(raw["grantedAt"]).map { Date(timeIntervalSince1970: $0) }
        )
    }

    // MARK: - 宽松取值

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.isEmpty == false ? value as? String : nil
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}

private extension Data {
    /// 去掉行首尾空白，供逐行 JSON 解析使用。
    func trimmingJSONWhitespace() -> Data {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        var start = startIndex
        var end = endIndex
        while start < end, whitespace.contains(self[start]) { start += 1 }
        while end > start, whitespace.contains(self[end - 1]) { end -= 1 }
        return subdata(in: start..<end)
    }
}
