//
//  TranslateService.swift
//  PasteDeck
//
//  Pluggable domestic translation APIs and OpenAI-compatible LLM translation.
//

import CryptoKit
import Foundation

// MARK: - Configuration

/// 常规翻译服务商类型；raw value 会写入设置 JSON，已有值不可随意调整。
enum TranslationProviderKind: String, Codable, CaseIterable, Identifiable {
    /// 百度翻译开放平台通用翻译 API。
    case baidu
    /// 腾讯云机器翻译 TextTranslate API 3.0。
    case tencent
    /// 网易有道智云文本翻译 API v3。
    case youdao
    /// 阿里云机器翻译通用版 ROA API。
    case alibaba

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baidu: return "百度翻译"
        case .tencent: return "腾讯云翻译"
        case .youdao: return "网易有道翻译"
        case .alibaba: return "阿里云翻译"
        }
    }

    var credentialIdTitle: String {
        switch self {
        case .baidu: return "App ID"
        case .tencent: return "Secret ID"
        case .youdao: return "应用 ID"
        case .alibaba: return "AccessKey ID"
        }
    }

    var credentialSecretTitle: String {
        switch self {
        case .baidu: return "密钥"
        case .tencent: return "Secret Key"
        case .youdao: return "应用密钥"
        case .alibaba: return "AccessKey Secret"
        }
    }
}

/// 一套常规翻译服务商配置，凭据目前跟随 AppSettings 保存在本机 SwiftData 中。
struct TranslationProviderConfiguration: Codable, Equatable {
    /// 服务商类型；候选值为 baidu、tencent、youdao、alibaba。
    var kind: TranslationProviderKind
    /// 设置页与翻译结果中展示的服务名称。
    var name: String
    /// 是否允许将该服务作为默认常规翻译入口。
    var enabled: Bool
    /// 服务商用于标识调用方的 App ID、Secret ID、应用 ID 或 AccessKey ID。
    var credentialId: String
    /// 服务商用于签名请求的密钥、Secret Key、应用密钥或 AccessKey Secret。
    var credentialSecret: String
    /// 腾讯云 API 地域，其他服务商保留该字段但不使用；常见值为 ap-guangzhou。
    var region: String
    /// 是否允许预览窗口并发翻译分段；仅在账号配额允许时开启。
    var allowsConcurrentRequests: Bool

    var isConfigured: Bool {
        enabled && !credentialId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !credentialSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 一套 OpenAI-compatible 大模型翻译配置，可在设置中保存多套并按需选择。
struct LLMTranslationConfiguration: Codable, Equatable, Identifiable {
    /// 配置稳定标识，用于列表编辑、测试结果关联和翻译菜单选择。
    var id: UUID
    /// 用户可识别的服务名称，例如“DeepSeek”或“公司网关”。
    var name: String
    /// OpenAI-compatible API 基础地址或完整 chat/completions 地址。
    var baseURL: String
    /// Bearer API Key；请求时仅通过 Authorization header 发送。
    var apiKey: String
    /// chat/completions 请求使用的模型标识，例如 deepseek-chat。
    var model: String
    /// 是否在翻译结果的“大模型重译”菜单中提供此配置。
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "大模型",
        baseURL: String = "",
        apiKey: String = "",
        model: String = "",
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.enabled = enabled
    }

    var isConfigured: Bool {
        enabled
            && URL(string: baseURL) != nil
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Translation Result

struct TranslateSegment: Identifiable {
    /// 当前分段的临时视图标识。
    let id = UUID()
    /// 当前分段从零开始的顺序。
    let index: Int
    /// 本次翻译包含的分段总数。
    let total: Int
    /// 当前分段的原文。
    let source: String
    /// 当前分段成功返回的译文。
    var result: String?
    /// 当前分段失败时面向用户的错误信息。
    var error: String?
    /// 当前分段是否正在等待服务端响应。
    var isTranslating: Bool = false
}

// MARK: - Translate Service

final class TranslateService {
    private let configuration: TranslationProviderConfiguration

    /// 国内翻译 API 的常见单次限制为 5,000-6,000 字符；按 4,500 字节拆分可兼容 UTF-8 中文与各平台限制。
    private let maxBytesPerRequest = 4500

    init(configuration: TranslationProviderConfiguration) {
        self.configuration = configuration
    }

    /// 兼容旧版预览窗口和旧设置数据的百度初始化入口。
    convenience init(appId: String, secretKey: String, isAdvanced: Bool = false) {
        self.init(configuration: TranslationProviderConfiguration(
            kind: .baidu,
            name: TranslationProviderKind.baidu.displayName,
            enabled: true,
            credentialId: appId,
            credentialSecret: secretKey,
            region: "ap-guangzhou",
            allowsConcurrentRequests: isAdvanced
        ))
    }

    // MARK: Text Splitting

    /// 将文本按段落和句子切分，并合并较短片段以降低调用次数和延迟。
    func splitText(_ text: String) -> [String] {
        let paragraphs = text.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var segments: [String] = []

        for paragraph in paragraphs {
            if paragraph.utf8.count <= maxBytesPerRequest {
                segments.append(paragraph)
                continue
            }

            var currentGroup = ""
            for sentence in splitSentences(paragraph) {
                let combined = currentGroup.isEmpty ? sentence : currentGroup + "\n" + sentence
                if combined.utf8.count <= maxBytesPerRequest {
                    currentGroup = combined
                } else {
                    if !currentGroup.isEmpty {
                        segments.append(currentGroup)
                    }
                    currentGroup = sentence
                }
            }
            if !currentGroup.isEmpty {
                segments.append(currentGroup)
            }
        }

        return mergeSmallSegments(segments)
    }

    private func splitSentences(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[。！？.!?]", options: []) else {
            return [text]
        }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var sentences: [String] = []
        var startIndex = 0

        for match in matches {
            let endIndex = match.range.location + match.range.length
            let sentence = source.substring(with: NSRange(location: startIndex, length: endIndex - startIndex))
            if !sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                sentences.append(sentence)
            }
            startIndex = endIndex
        }
        if startIndex < source.length {
            sentences.append(source.substring(from: startIndex))
        }

        return sentences.isEmpty ? [text] : sentences
    }

    private func mergeSmallSegments(_ segments: [String]) -> [String] {
        var result: [String] = []
        var current = ""

        for segment in segments {
            let combined = current.isEmpty ? segment : current + "\n" + segment
            if combined.utf8.count <= maxBytesPerRequest {
                current = combined
            } else {
                if !current.isEmpty {
                    result.append(current)
                }
                current = segment
            }
        }
        if !current.isEmpty {
            result.append(current)
        }

        return result
    }

    // MARK: API Call

    func translateSegment(
        _ text: String,
        from: String = "auto",
        to: String = "zh",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard configuration.isConfigured else {
            completion(.failure(TranslateError.notConfigured))
            return
        }

        switch configuration.kind {
        case .baidu:
            translateWithBaidu(text, from: from, to: to, completion: completion)
        case .tencent:
            translateWithTencent(text, from: from, to: to, completion: completion)
        case .youdao:
            translateWithYoudao(text, from: from, to: to, completion: completion)
        case .alibaba:
            translateWithAlibaba(text, from: from, to: to, completion: completion)
        }
    }

    private func translateWithBaidu(
        _ text: String,
        from: String,
        to: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let salt = String(Int.random(in: 100000...999999))
        let rawSignature = configuration.credentialId + text + salt + configuration.credentialSecret
        let signature = Insecure.MD5.hash(data: Data(rawSignature.utf8)).hexString
        var components = URLComponents(string: "https://api.fanyi.baidu.com/api/trans/vip/translate")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "appid", value: configuration.credentialId),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: signature)
        ]
        guard let url = components?.url else {
            completion(.failure(TranslateError.invalidURL))
            return
        }

        performJSONRequest(URLRequest(url: url)) { json in
            if let code = json["error_code"] as? String {
                throw TranslateError.apiError(
                    provider: self.configuration.name,
                    code: code,
                    message: json["error_msg"] as? String ?? "未知错误"
                )
            }
            guard let rows = json["trans_result"] as? [[String: Any]] else {
                throw TranslateError.invalidResponse
            }
            return rows.compactMap { $0["dst"] as? String }.joined(separator: "\n")
        } completion: { completion($0) }
    }

    private func translateWithYoudao(
        _ text: String,
        from: String,
        to: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let salt = UUID().uuidString
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let input = Self.youdaoSignatureInput(text)
        let rawSignature = configuration.credentialId + input + salt + timestamp + configuration.credentialSecret
        let signature = SHA256.hash(data: Data(rawSignature.utf8)).hexString
        guard let url = URL(string: "https://openapi.youdao.com/api") else {
            completion(.failure(TranslateError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "appKey", value: configuration.credentialId),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: signature),
            URLQueryItem(name: "signType", value: "v3"),
            URLQueryItem(name: "curtime", value: timestamp)
        ].percentEncodedQuery?.data(using: .utf8)

        performJSONRequest(request) { json in
            let code = json["errorCode"] as? String ?? ""
            guard code == "0" else {
                throw TranslateError.apiError(provider: self.configuration.name, code: code, message: "请求失败")
            }
            guard let translation = json["translation"] as? [String] else {
                throw TranslateError.invalidResponse
            }
            return translation.joined(separator: "\n")
        } completion: { completion($0) }
    }

    private func translateWithTencent(
        _ text: String,
        from: String,
        to: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let host = "tmt.tencentcloudapi.com"
        let service = "tmt"
        let timestamp = Int(Date().timeIntervalSince1970)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        let sourceLanguage = from == "auto" ? (to == "zh" ? "en" : "zh") : from
        let bodyObject: [String: Any] = [
            "SourceText": text,
            "Source": sourceLanguage,
            "Target": to,
            "ProjectId": 0
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyObject),
              let url = URL(string: "https://\(host)") else {
            completion(.failure(TranslateError.invalidURL))
            return
        }

        let contentType = "application/json; charset=utf-8"
        let signedHeaders = "content-type;host"
        let canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\n"
        let hashedPayload = SHA256.hash(data: body).hexString
        let canonicalRequest = "POST\n/\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(hashedPayload)"
        let credentialScope = "\(date)/\(service)/tc3_request"
        let stringToSign = "TC3-HMAC-SHA256\n\(timestamp)\n\(credentialScope)\n\(SHA256.hash(data: Data(canonicalRequest.utf8)).hexString)"
        let secretDate = Self.hmacSHA256(Data(date.utf8), key: Data(("TC3" + configuration.credentialSecret).utf8))
        let secretService = Self.hmacSHA256(Data(service.utf8), key: secretDate)
        let secretSigning = Self.hmacSHA256(Data("tc3_request".utf8), key: secretService)
        let signature = Self.hmacSHA256(Data(stringToSign.utf8), key: secretSigning).hexString
        let authorization = "TC3-HMAC-SHA256 Credential=\(configuration.credentialId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue("TextTranslate", forHTTPHeaderField: "X-TC-Action")
        request.setValue("2018-03-21", forHTTPHeaderField: "X-TC-Version")
        request.setValue(configuration.region.isEmpty ? "ap-guangzhou" : configuration.region, forHTTPHeaderField: "X-TC-Region")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        performJSONRequest(request) { json in
            guard let response = json["Response"] as? [String: Any] else {
                throw TranslateError.invalidResponse
            }
            if let error = response["Error"] as? [String: Any] {
                throw TranslateError.apiError(
                    provider: self.configuration.name,
                    code: error["Code"] as? String ?? "unknown",
                    message: error["Message"] as? String ?? "未知错误"
                )
            }
            guard let result = response["TargetText"] as? String else {
                throw TranslateError.invalidResponse
            }
            return result
        } completion: { completion($0) }
    }

    private func translateWithAlibaba(
        _ text: String,
        from: String,
        to: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let resource = "/api/translate/web/general"
        guard let url = URL(string: "https://mt.cn-hangzhou.aliyuncs.com\(resource)") else {
            completion(.failure(TranslateError.invalidURL))
            return
        }
        let bodyObject: [String: Any] = [
            "FormatType": "text",
            "SourceLanguage": from,
            "TargetLanguage": to,
            "SourceText": text,
            "Scene": "general"
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyObject) else {
            completion(.failure(TranslateError.invalidResponse))
            return
        }

        let accept = "application/json"
        let contentType = "application/json;charset=utf-8"
        let contentMD5 = Data(Insecure.MD5.hash(data: body)).base64EncodedString()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let date = dateFormatter.string(from: Date())
        let nonce = UUID().uuidString
        let canonicalHeaders = "x-acs-signature-method:HMAC-SHA1\nx-acs-signature-nonce:\(nonce)\nx-acs-version:2019-01-02\n"
        let stringToSign = "POST\n\(accept)\n\(contentMD5)\n\(contentType)\n\(date)\n\(canonicalHeaders)\(resource)"
        let signature = Data(HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: Data(configuration.credentialSecret.utf8))
        )).base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentMD5, forHTTPHeaderField: "Content-MD5")
        request.setValue(date, forHTTPHeaderField: "Date")
        request.setValue("HMAC-SHA1", forHTTPHeaderField: "x-acs-signature-method")
        request.setValue(nonce, forHTTPHeaderField: "x-acs-signature-nonce")
        request.setValue("2019-01-02", forHTTPHeaderField: "x-acs-version")
        request.setValue("acs \(configuration.credentialId):\(signature)", forHTTPHeaderField: "Authorization")

        performJSONRequest(request) { json in
            if let errorCode = json["errorCode"] as? String {
                throw TranslateError.apiError(
                    provider: self.configuration.name,
                    code: errorCode,
                    message: json["errorMsg"] as? String ?? "未知错误"
                )
            }
            if let data = json["Data"] as? [String: Any], let translated = data["Translated"] as? String {
                return translated
            }
            if let response = json["TranslateGeneralResponse"] as? [String: Any],
               let data = response["Data"] as? [String: Any],
               let translated = data["Translated"] as? String {
                return translated
            }
            throw TranslateError.invalidResponse
        } completion: { completion($0) }
    }

    private func performJSONRequest(
        _ request: URLRequest,
        parser: @escaping ([String: Any]) throws -> String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                completion(.failure(TranslateError.noData))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw TranslateError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    let message = json["Message"] as? String ?? json["message"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    throw TranslateError.apiError(provider: self.configuration.name, code: String(httpResponse.statusCode), message: message)
                }
                completion(.success(try parser(json)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private static func youdaoSignatureInput(_ text: String) -> String {
        guard text.count > 20 else { return text }
        return String(text.prefix(10)) + String(text.count) + String(text.suffix(10))
    }

    private static func hmacSHA256(_ data: Data, key: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    /// 自动检测目标语言：中文占比超过三分之一时译为英文，否则译为简体中文。
    static func detectTargetLanguage(for text: String) -> String {
        let chineseRange = CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")
        let chineseCount = text.unicodeScalars.filter { chineseRange.contains($0) }.count
        return chineseCount > text.unicodeScalars.count / 3 ? "en" : "zh"
    }
}

// MARK: - LLM Translation

final class LLMTranslationService {
    private let configuration: LLMTranslationConfiguration

    init(configuration: LLMTranslationConfiguration) {
        self.configuration = configuration
    }

    func translate(
        _ text: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard configuration.isConfigured,
              let url = Self.chatCompletionsURL(from: configuration.baseURL) else {
            completion(.failure(TranslateError.notConfigured))
            return
        }
        let targetDescription = targetLanguage == "en" ? "English" : "Simplified Chinese"
        let bodyObject: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": "You are a professional translator. Translate faithfully into \(targetDescription). Return only the translation, without explanations."],
                ["role": "user", "content": text]
            ],
            "temperature": 0.2,
            "stream": false
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyObject) else {
            completion(.failure(TranslateError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let httpResponse = response as? HTTPURLResponse,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(TranslateError.invalidResponse))
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorObject = json["error"] as? [String: Any]
                completion(.failure(TranslateError.apiError(
                    provider: self.configuration.name,
                    code: String(httpResponse.statusCode),
                    message: errorObject?["message"] as? String ?? "请求失败"
                )))
                return
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(.failure(TranslateError.invalidResponse))
                return
            }
            completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }

    private static func chatCompletionsURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")
    }
}

// MARK: - Errors and Crypto Helpers

enum TranslateError: LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case apiError(provider: String, code: String, message: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的请求地址"
        case .noData: return "未收到响应数据"
        case .invalidResponse: return "服务返回格式异常"
        case .apiError(let provider, let code, let message): return "\(provider)错误 \(code)：\(message)"
        case .notConfigured: return "翻译服务尚未完成配置"
        }
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Array where Element == URLQueryItem {
    var percentEncodedQuery: String? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery
    }
}
