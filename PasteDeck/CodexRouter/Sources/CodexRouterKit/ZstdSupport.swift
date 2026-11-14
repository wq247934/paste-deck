//
//  ZstdSupport.swift
//  PasteDeck
//
//  zstd 压缩/解压封装。解压走 AgentSpeed 的 CZstd，压缩走 CZstdCompress
//  （同版本 zstd 1.5.7）。语义对齐 router.mjs 的 compressedNativeBody：
//  ≥16KB 且压得过小才启用 Content-Encoding: zstd；失败一律回退原文。
//

import Foundation
import CZstd
import CZstdCompress

enum ZstdError: Error {
    case decompressionFailed(UInt)
    case compressionFailed(UInt)
}

enum ZstdSupport {

    /// Codex 客户端压缩请求体的大小上限（256MB，对齐 MAX_DECODED_BODY_BYTES）。
    static let maxDecodedBytes = 256 * 1024 * 1024

    /// 原生转发的再压缩阈值（16KB）。
    static let minCompressedBodyBytes = 16 * 1024

    /// 解压（流式 API，支持大请求体）。
    static func decompress(_ data: Data) throws -> Data {
        var output = Data()
        let chunkSize = 1 << 20
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var stream = ZSTD_inBuffer(src: data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress },
                                   size: data.count, pos: 0)
        guard let dctx = ZSTD_createDCtx() else { throw ZstdError.decompressionFailed(0) }
        defer { ZSTD_freeDCtx(dctx) }
        while stream.pos < stream.size {
            var out = ZSTD_outBuffer(dst: &buffer, size: chunkSize, pos: 0)
            let result = ZSTD_decompressStream(dctx, &out, &stream)
            if ZSTD_isError(result) != 0 {
                throw ZstdError.decompressionFailed(UInt(ZSTD_getErrorCode(result).rawValue))
            }
            output.append(contentsOf: buffer[0..<out.pos])
            if output.count > maxDecodedBytes {
                throw ZstdError.decompressionFailed(UInt.max)
            }
        }
        return output
    }

    /// 压缩（流式 API）。返回 nil 表示压缩失败——调用方回退原文。
    static func compress(_ data: Data, level: Int32 = 3) -> Data? {
        guard !data.isEmpty else { return nil }
        let bound = ZSTD_compressBound(data.count)
        guard bound > 0 else { return nil }
        var output = [UInt8](repeating: 0, count: bound)
        let result = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return ZSTD_compress(&output, bound, base, data.count, level)
        }
        guard ZSTD_isError(result) == 0 else { return nil }
        return Data(output[0..<result])
    }

    /// 原生转发的请求体压缩策略：小于阈值或压不小时回退原文。
    /// 返回 (body, 是否带 Content-Encoding: zstd)。
    static func compressNativeBodyIfBeneficial(_ body: Data) -> (Data, Bool) {
        guard body.count >= minCompressedBodyBytes,
              let compressed = compress(body),
              compressed.count < body.count else {
            return (body, false)
        }
        return (compressed, true)
    }
}
