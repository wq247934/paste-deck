//
//  IPGeoService.swift
//  PasteDeck
//
//  IPv4 归属地/运营商在线查询：仅在用户点击查询时把该 IP 发送给
//  免费公开接口（ipwho.is 主源，ipinfo.io 备源），不携带任何其他
//  用户数据，不记录日志。私网/保留地址直接拒绝，不发起网络请求。
//

import Foundation

struct IPGeoResult: Equatable {
    /// 归属地（国家 / 省州 / 城市）。
    let location: String
    /// 运营商或所属组织。
    let isp: String
    /// AS 号。
    let asn: String?
    /// IP 所处时区。
    let timezone: String?
    /// 数据来源站点。
    let source: String
}

enum IPGeoError: LocalizedError {
    case privateAddress
    case invalidResponse
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .privateAddress:
            return "私有或保留地址没有公网归属地信息"
        case .invalidResponse:
            return "接口返回数据无法解析"
        case .queryFailed(let message):
            return message
        }
    }
}

enum IPGeoService {

    private static let primarySource = "ipwho.is"
    private static let fallbackSource = "ipinfo.io"

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }

    /// 私网 / 回环 / 链路本地 / 保留地址一律不发起网络查询。
    static func isQueryable(_ address: IPv4Math.Address) -> Bool {
        switch IPv4Math.kind(of: address) {
        case .publicAddress:
            return true
        case .unspecified, .loopback, .privateNetwork, .linkLocal,
             .carrierGradeNAT, .multicast, .reserved:
            return false
        }
    }

    static func query(_ address: IPv4Math.Address) async throws -> IPGeoResult {
        guard isQueryable(address) else {
            throw IPGeoError.privateAddress
        }
        do {
            return try await queryIPWhoIs(address.dottedString)
        } catch {
            // 主源失败（超时 / 限流 / 解析失败）时退到备源。
            return try await queryIPInfo(address.dottedString)
        }
    }

    // MARK: - ipwho.is

    private static func queryIPWhoIs(_ ip: String) async throws -> IPGeoResult {
        guard let url = URL(string: "https://ipwho.is/\(ip)") else {
            throw IPGeoError.invalidResponse
        }
        let (data, response) = try await makeSession().data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw IPGeoError.queryFailed("\(primarySource) 返回 \( (response as? HTTPURLResponse)?.statusCode ?? -1 )")
        }
        return try parseIPWhoIs(data)
    }

    static func parseIPWhoIs(_ data: Data) throws -> IPGeoResult {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IPGeoError.invalidResponse
        }
        if payload["success"] as? Bool == false {
            let message = payload["message"] as? String ?? "查询失败"
            throw IPGeoError.queryFailed(message)
        }

        let country = payload["country"] as? String
        let region = payload["region"] as? String
        let city = payload["city"] as? String
        let location = [country, region, city]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        guard !location.isEmpty else {
            throw IPGeoError.invalidResponse
        }

        let connection = payload["connection"] as? [String: Any]
        let isp = (connection?["isp"] as? String)
            ?? (connection?["org"] as? String)
            ?? (payload["org"] as? String)
            ?? "未知"
        let asnValue = connection?["asn"] as? Int
        let asn = asnValue.map { "AS\($0)" }
        let timezone = (payload["timezone"] as? [String: Any])?["id"] as? String

        return IPGeoResult(
            location: location,
            isp: isp,
            asn: asn,
            timezone: timezone,
            source: primarySource
        )
    }

    // MARK: - ipinfo.io（备源）

    private static func queryIPInfo(_ ip: String) async throws -> IPGeoResult {
        guard let url = URL(string: "https://ipinfo.io/\(ip)/json") else {
            throw IPGeoError.invalidResponse
        }
        let (data, response) = try await makeSession().data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw IPGeoError.queryFailed("\(fallbackSource) 返回 \( (response as? HTTPURLResponse)?.statusCode ?? -1 )")
        }
        return try parseIPInfo(data)
    }

    static func parseIPInfo(_ data: Data) throws -> IPGeoResult {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IPGeoError.invalidResponse
        }
        if payload["error"] != nil {
            let message = (payload["error"] as? [String: Any])?["title"] as? String ?? "查询失败"
            throw IPGeoError.queryFailed(message)
        }

        let country = (payload["country"] as? String).map(Self.countryName) ?? ""
        let region = payload["region"] as? String
        let city = payload["city"] as? String
        let location = [country, region, city]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        guard !location.isEmpty else {
            throw IPGeoError.invalidResponse
        }

        return IPGeoResult(
            location: location,
            isp: payload["org"] as? String ?? "未知",
            asn: (payload["org"] as? String).flatMap { org in
                org.hasPrefix("AS") ? String(org.prefix(while: { !$0.isWhitespace })) : nil
            },
            timezone: payload["timezone"] as? String,
            source: fallbackSource
        )
    }

    /// ipinfo 的国家字段是两位代码，转换常用国家；未收录时原样返回。
    static func countryName(_ code: String) -> String {
        switch code.uppercased() {
        case "CN": return "China"
        case "US": return "United States"
        case "JP": return "Japan"
        case "KR": return "South Korea"
        case "HK": return "Hong Kong"
        case "TW": return "Taiwan"
        case "SG": return "Singapore"
        case "DE": return "Germany"
        case "GB": return "United Kingdom"
        case "FR": return "France"
        case "CA": return "Canada"
        case "AU": return "Australia"
        case "RU": return "Russia"
        case "IN": return "India"
        default: return code
        }
    }
}
