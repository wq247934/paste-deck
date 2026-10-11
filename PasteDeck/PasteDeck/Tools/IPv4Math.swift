//
//  IPv4Math.swift
//  PasteDeck
//
//  IPv4 地址与子网的纯计算逻辑，全部基于 UInt32 位运算。
//  正确处理 /0、/31、/32 等边界前缀。
//

import Foundation

enum IPv4Math {

    // MARK: - 地址

    struct Address: Equatable, Hashable {
        let value: UInt32

        var dottedString: String {
            [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
                .map(String.init)
                .joined(separator: ".")
        }

        /// 严格解析点分十进制：4 段、每段 1–3 位 ASCII 数字且不超过 255。
        static func parse(_ raw: String?) -> Address? {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }

            let octets = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4 else { return nil }

            var value: UInt32 = 0
            for octet in octets {
                guard (1...3).contains(octet.count),
                      octet.allSatisfy({ $0.isASCII && $0.isWholeNumber }),
                      let octetValue = UInt32(octet),
                      octetValue <= 255 else {
                    return nil
                }
                value = (value << 8) | octetValue
            }
            return Address(value: value)
        }
    }

    // MARK: - 地址类型

    enum AddressKind: Equatable {
        case unspecified
        case loopback
        case privateNetwork
        case linkLocal
        case carrierGradeNAT
        case multicast
        case reserved
        case publicAddress

        var displayName: String {
            switch self {
            case .unspecified: return "未指定地址"
            case .loopback: return "回环地址"
            case .privateNetwork: return "私网地址"
            case .linkLocal: return "链路本地"
            case .carrierGradeNAT: return "运营商级 NAT"
            case .multicast: return "组播地址"
            case .reserved: return "保留地址"
            case .publicAddress: return "公网地址"
            }
        }
    }

    private static func contains(_ address: Address, network: UInt32, prefix: Int) -> Bool {
        guard prefix > 0 else { return true }
        let mask = UInt32.max << (32 - prefix)
        return (address.value & mask) == network
    }

    static func kind(of address: Address) -> AddressKind {
        let value = address.value
        if value == 0 { return .unspecified }
        if value == 0xFFFF_FFFF { return .reserved }
        if contains(address, network: 0x7F00_0000, prefix: 8) { return .loopback }
        if contains(address, network: 0x0A00_0000, prefix: 8) { return .privateNetwork }
        if contains(address, network: 0xAC10_0000, prefix: 12) { return .privateNetwork }
        if contains(address, network: 0xC0A8_0000, prefix: 16) { return .privateNetwork }
        if contains(address, network: 0xA9FE_0000, prefix: 16) { return .linkLocal }
        if contains(address, network: 0x6440_0000, prefix: 10) { return .carrierGradeNAT }
        if contains(address, network: 0xE000_0000, prefix: 4) { return .multicast }
        if contains(address, network: 0xF000_0000, prefix: 4) { return .reserved }
        return .publicAddress
    }

    // MARK: - 子网

    struct Subnet: Equatable {
        /// 输入的主机地址。
        let inputAddress: Address
        let prefixLength: Int
        let network: Address
        let broadcast: Address
        let mask: Address
        let wildcardMask: Address
        /// 地址总数（含网络地址与广播地址）。
        let totalAddressCount: UInt64
        /// 可用主机数；/31 按 RFC 3021 为 2，/32 为 1。
        let usableAddressCount: UInt64
        let firstUsable: Address
        let lastUsable: Address

        /// /32 没有独立的网络/广播地址语义，界面据此隐藏对应行。
        var isSingleHost: Bool { prefixLength == 32 }
    }

    static func mask(forPrefixLength prefix: Int) -> UInt32? {
        guard (0...32).contains(prefix) else { return nil }
        guard prefix > 0 else { return 0 }
        return UInt32.max << (32 - prefix)
    }

    /// 由主机地址与前缀长度推算子网；输入地址会被掩码归一化到网络地址。
    static func subnet(address: Address, prefixLength: Int) -> Subnet? {
        guard let maskValue = mask(forPrefixLength: prefixLength) else { return nil }

        let networkValue = address.value & maskValue
        let broadcastValue = networkValue | ~maskValue
        let total = UInt64(1) << UInt64(32 - prefixLength)

        let firstUsable: UInt32
        let lastUsable: UInt32
        let usableCount: UInt64
        switch prefixLength {
        case 32:
            firstUsable = networkValue
            lastUsable = networkValue
            usableCount = 1
        case 31:
            // RFC 3021：点对点链路两个地址均可用。
            firstUsable = networkValue
            lastUsable = broadcastValue
            usableCount = 2
        default:
            firstUsable = networkValue + 1
            lastUsable = broadcastValue - 1
            usableCount = total - 2
        }

        return Subnet(
            inputAddress: address,
            prefixLength: prefixLength,
            network: Address(value: networkValue),
            broadcast: Address(value: broadcastValue),
            mask: Address(value: maskValue),
            wildcardMask: Address(value: ~maskValue),
            totalAddressCount: total,
            usableAddressCount: usableCount,
            firstUsable: Address(value: firstUsable),
            lastUsable: Address(value: lastUsable)
        )
    }

    /// 解析 "a.b.c.d"（按 /32 单主机处理）或 "a.b.c.d/p"（CIDR）。
    static func parseSubnet(_ raw: String?) -> (address: Address, subnet: Subnet)? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let address = Address.parse(String(parts[0])),
                  (1...3).contains(parts[1].count),
                  parts[1].allSatisfy({ $0.isASCII && $0.isWholeNumber }),
                  let prefix = Int(parts[1]),
                  let subnet = subnet(address: address, prefixLength: prefix) else {
                return nil
            }
            return (address, subnet)
        }

        guard let address = Address.parse(trimmed),
              let subnet = subnet(address: address, prefixLength: 32) else {
            return nil
        }
        return (address, subnet)
    }
}
