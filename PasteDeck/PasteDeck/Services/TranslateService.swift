//
//  TranslateService.swift
//  PasteDeck
//
//  Baidu Translate API service with paragraph splitting and serial/parallel calls.
//

import Foundation
import CryptoKit

// MARK: - Translation Result

struct TranslateSegment: Identifiable {
    let id = UUID()
    let index: Int
    let total: Int
    let source: String
    var result: String?
    var error: String?
    var isTranslating: Bool = false
}

// MARK: - Translate Service

class TranslateService {
    private let appId: String
    private let secretKey: String
    private let isAdvanced: Bool

    /// 百度翻译 API 单次请求最大字节数
    private let maxBytesPerRequest = 6000

    init(appId: String, secretKey: String, isAdvanced: Bool = false) {
        self.appId = appId
        self.secretKey = secretKey
        self.isAdvanced = isAdvanced
    }

    // MARK: - Text Splitting

    /// 将文本按段落拆分，超长段落按句子拆分后贪心合并
    func splitText(_ text: String) -> [String] {
        let paragraphs = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var segments: [String] = []
        for paragraph in paragraphs {
            let byteCount = paragraph.utf8.count
            if byteCount <= maxBytesPerRequest {
                segments.append(paragraph)
            } else {
                // 按句子拆分后贪心合并
                let sentences = splitSentences(paragraph)
                var currentGroup = ""
                for sentence in sentences {
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
        }

        // 合并小段落以减少 API 调用次数
        return mergeSmallSegments(segments)
    }

    /// 按句子标点拆分（中英文句号、问号、感叹号）
    private func splitSentences(_ text: String) -> [String] {
        let pattern = "[。！？.!?]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var sentences: [String] = []
        var start = 0
        for match in matches {
            let end = match.range.location + match.range.length
            let sentence = nsText.substring(with: NSRange(location: start, length: end - start))
            if !sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                sentences.append(sentence)
            }
            start = end
        }
        // 剩余部分
        if start < nsText.length {
            let remaining = nsText.substring(from: start)
            if !remaining.trimmingCharacters(in: .whitespaces).isEmpty {
                sentences.append(remaining)
            }
        }

        return sentences.isEmpty ? [text] : sentences
    }

    /// 贪心合并小段落，减少 API 调用
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

    // MARK: - API Call

    /// 翻译单段文本
    func translateSegment(
        _ text: String,
        from: String = "auto",
        to: String = "zh",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let salt = String(Int.random(in: 100000...999999))
        let sign = generateSign(q: text, salt: salt)

        var components = URLComponents(string: "https://api.fanyi.baidu.com/api/trans/vip/translate")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "appid", value: appId),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
        ]

        guard let url = components.url else {
            completion(.failure(TranslateError.invalidURL))
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(TranslateError.noData))
                return
            }

            // 解析响应
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                if let errorCode = json?["error_code"] as? String,
                   let errorMsg = json?["error_msg"] as? String {
                    completion(.failure(TranslateError.apiError(code: errorCode, message: errorMsg)))
                    return
                }

                guard let transResult = json?["trans_result"] as? [[String: String]] else {
                    completion(.failure(TranslateError.invalidResponse))
                    return
                }

                let translated = transResult.compactMap { $0["dst"] }.joined(separator: "\n")
                completion(.success(translated))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// 生成百度翻译签名: MD5(appid+q+salt+密钥)
    private func generateSign(q: String, salt: String) -> String {
        let raw = appId + q + salt + secretKey
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 自动检测目标语言：如果文本主要是中文则译为英文，否则译为中文
    static func detectTargetLanguage(for text: String) -> String {
        let chineseCount = text.unicodeScalars.filter { CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}").contains($0) }.count
        let total = text.unicodeScalars.count
        return chineseCount > total / 3 ? "en" : "zh"
    }
}

// MARK: - Errors

enum TranslateError: LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case apiError(code: String, message: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的请求地址"
        case .noData: return "未收到响应数据"
        case .invalidResponse: return "响应格式异常"
        case .apiError(let code, let msg): return "百度翻译错误 \(code): \(msg)"
        case .notConfigured: return "未配置百度翻译 API"
        }
    }
}
