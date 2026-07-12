//
//  ImageOCRService.swift
//  PasteDeck
//
//  Runs OCR for cached clipboard images off the main thread.
//

import Foundation
import Vision

final class ImageOCRService {
    static let shared = ImageOCRService()

    private let queue = DispatchQueue(label: "com.pastedeck.image-ocr", qos: .utility)
    private let lock = NSLock()
    private var inFlightPaths: Set<String> = []

    private init() {}

    func recognizeText(inImageAt path: String, completion: @escaping (String?) -> Void) {
        guard begin(path) else { return }

        queue.async { [weak self] in
            let text = Self.recognizeText(at: URL(fileURLWithPath: path))
            self?.finish(path)

            DispatchQueue.main.async {
                completion(text)
            }
        }
    }

    private func begin(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !inFlightPaths.contains(path) else { return false }
        inFlightPaths.insert(path)
        return true
    }

    private func finish(_ path: String) {
        lock.lock()
        inFlightPaths.remove(path)
        lock.unlock()
    }

    private static func recognizeText(at url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("[PasteDeck] OCR failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        // Vision 不保证 observations 的返回顺序；按屏幕阅读顺序排序，避免不同渲染框架下译文行序错乱。
        let lines = (request.results ?? [])
            .compactMap { observation -> (text: String, boundingBox: CGRect)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : (text: text, boundingBox: observation.boundingBox)
            }
            .sorted { first, second in
                let verticalDifference = abs(first.boundingBox.midY - second.boundingBox.midY)
                if verticalDifference < 0.02 {
                    return first.boundingBox.minX < second.boundingBox.minX
                }
                return first.boundingBox.midY > second.boundingBox.midY
            }
            .map(\.text)

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }
}
