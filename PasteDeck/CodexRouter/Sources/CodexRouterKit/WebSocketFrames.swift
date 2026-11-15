//
//  WebSocketFrames.swift
//  PasteDeck
//
//  RFC 6455 帧编解码（服务端视角）：仅文本帧、客户端必须掩码、
//  服务端不掩码；拒绝协商扩展。语义对齐 ws-frames.mjs。
//

import Foundation

enum WebSocketCloseCode: UInt16 {
    case normal = 1000
    case protocolError = 1002
    case unsupportedData = 1003
    case invalidPayload = 1007
    case policyViolation = 1008
    case messageTooBig = 1009
    case internalError = 1011
}

enum WebSocketFrameError: Error, Equatable {
    case incomplete
    case protocolViolation(String)
    case binaryFrame
    case invalidMasking
    case oversizedMessage
    case invalidUTF8
}

/// 解析出的单帧。
struct WebSocketFrame {
    var fin: Bool
    var opcode: UInt8
    var payload: Data
}

/// 帧解码器（逐帧累积解析）。
/// - 服务端模式（默认）：客户端帧必须掩码（RFC 6455 强制）。
/// - 客户端模式（requireMasking=false）：解析服务端下行帧（不掩码）。
final class WebSocketFrameDecoder {
    static let maxMessageBytes = 32 * 1024 * 1024
    static let maxFragmentFrames = 1024

    private let requireMasking: Bool
    private var buffered = Data()
    private(set) var messageBuffer = Data()
    private var fragmentOpcode: UInt8?
    private var fragmentCount = 0

    init(requireMasking: Bool = true) {
        self.requireMasking = requireMasking
    }

    /// 一次性解析缓冲区中所有完整帧；返回帧数组与剩余未消费字节数说明。
    /// 抛错表示协议违规，调用方应关闭连接。
    func feed(_ data: Data) throws -> [WebSocketFrame] {
        buffered.append(data)
        var frames: [WebSocketFrame] = []
        while true {
            guard let frame = try parseOne() else { break }
            // 帧级别处理：聚合分片。
            switch frame.opcode {
            case 0x1:
                if fragmentOpcode != nil {
                    throw WebSocketFrameError.protocolViolation("新数据帧出现在分片中间")
                }
                if frame.fin {
                    frames.append(frame)
                } else {
                    fragmentOpcode = frame.opcode
                    fragmentCount = 1
                    messageBuffer = frame.payload
                    try checkMessageBounds()
                }
            case 0x2:
                throw WebSocketFrameError.binaryFrame
            case 0x0:
                guard fragmentOpcode != nil else {
                    throw WebSocketFrameError.protocolViolation("意外的延续帧")
                }
                fragmentCount += 1
                messageBuffer.append(frame.payload)
                try checkMessageBounds()
                if fragmentCount > Self.maxFragmentFrames {
                    throw WebSocketFrameError.protocolViolation("分片数超限")
                }
                if frame.fin {
                    let assembled = WebSocketFrame(fin: true, opcode: fragmentOpcode!, payload: messageBuffer)
                    fragmentOpcode = nil
                    messageBuffer = Data()
                    fragmentCount = 0
                    frames.append(assembled)
                }
            case 0x8, 0x9, 0xA:
                // 控制 帧：必须 FIN 且 ≤125 字节。
                if !frame.fin { throw WebSocketFrameError.protocolViolation("控制帧必须 FIN") }
                if frame.payload.count > 125 { throw WebSocketFrameError.protocolViolation("控制帧负载超限") }
                frames.append(frame)
            default:
                throw WebSocketFrameError.protocolViolation("未知操作码 \(frame.opcode)")
            }
        }
        return frames
    }

    private func checkMessageBounds() throws {
        if messageBuffer.count > Self.maxMessageBytes {
            throw WebSocketFrameError.oversizedMessage
        }
    }

    /// 返回 nil 表示缓冲不足。
    private func parseOne() throws -> WebSocketFrame? {
        let bytes = [UInt8](buffered)
        guard bytes.count >= 2 else { return nil }
        let first = bytes[0]
        let second = bytes[1]
        let fin = (first & 0x80) != 0
        let opcode = first & 0x0F
        if (first & 0x70) != 0 {
            throw WebSocketFrameError.protocolViolation("RSV 位被设置（扩展未协商）")
        }
        let masked = (second & 0x80) != 0
        guard masked || !requireMasking else {
            throw WebSocketFrameError.invalidMasking
        }
        var index = 2
        var length = UInt64(second & 0x7F)
        if length == 126 {
            guard bytes.count >= 4 else { return nil }
            length = (UInt64(bytes[2]) << 8) | UInt64(bytes[3])
            index = 4
        } else if length == 127 {
            guard bytes.count >= 10 else { return nil }
            length = 0
            for shift in stride(from: 56, through: 0, by: -8) {
                length |= UInt64(bytes[index]) << UInt64(shift)
                index += 1
            }
        }
        // 掩码仅存在于客户端帧（RFC 6455）：无掩码帧不预留 4 字节掩码位。
        guard bytes.count >= index + (masked ? 4 : 0) else { return nil }
        let mask: [UInt8]
        if masked {
            mask = Array(bytes[index..<(index + 4)])
            index += 4
        } else {
            mask = []
        }
        guard bytes.count >= index + Int(length) else { return nil }
        var payload = Array(bytes[index..<(index + Int(length))])
        if masked {
            for offset in 0..<payload.count {
                payload[offset] ^= mask[offset % 4]
            }
        }
        buffered = Data(bytes[(index + Int(length))...])
        return WebSocketFrame(fin: fin, opcode: opcode, payload: Data(payload))
    }
}

enum WebSocketFrameEncoder {
    /// 服务端发出的一帧（不掩码）。
    static func textFrame(_ payload: Data) -> Data {
        encode(fin: true, opcode: 0x1, payload: payload, masked: false)
    }

    static func textFrame(_ text: String) -> Data {
        textFrame(Data(text.utf8))
    }

    static func closeFrame(code: WebSocketCloseCode, reason: String = "") -> Data {
        var payload = Data()
        var bigEndian = code.rawValue.bigEndian
        withUnsafeBytes(of: &bigEndian) { payload.append(contentsOf: $0) }
        payload.append(Data(reason.utf8))
        return encode(fin: true, opcode: 0x8, payload: payload, masked: false)
    }

    static func pongFrame(_ payload: Data) -> Data {
        encode(fin: true, opcode: 0xA, payload: payload, masked: false)
    }

    static func encode(fin: Bool, opcode: UInt8, payload: Data, masked: Bool) -> Data {
        var frame = Data()
        frame.appendUInt8((fin ? 0x80 : 0) | opcode)
        let length = payload.count
        if length < 126 {
            frame.appendUInt8((masked ? 0x80 : 0) | UInt8(length))
        } else if length <= 0xFFFF {
            frame.appendUInt8((masked ? 0x80 : 0) | 126)
            frame.appendUInt8(UInt8((length >> 8) & 0xFF))
            frame.appendUInt8(UInt8(length & 0xFF))
        } else {
            frame.appendUInt8((masked ? 0x80 : 0) | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.appendUInt8(UInt8((UInt64(length) >> UInt64(shift)) & 0xFF))
            }
        }
        if masked {
            var mask = [UInt8](repeating: 0, count: 4)
            _ = SecRandomCopyBytes(kSecRandomDefault, 4, &mask)
            frame.append(contentsOf: mask)
            let bytes = [UInt8](payload)
            frame.append(contentsOf: bytes.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        } else {
            frame.append(payload)
        }
        return frame
    }
}

private extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(contentsOf: [value])
    }
}
