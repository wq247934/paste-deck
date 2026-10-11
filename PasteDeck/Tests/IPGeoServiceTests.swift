//
//  IPGeoServiceTests.swift
//  PasteDeck
//
//  验证 IP 归属地查询的纯解析逻辑与私有地址防护。
//

import Foundation
import XCTest
@testable import PasteDeck

final class IPGeoServiceTests: XCTestCase {

    // MARK: - 私有地址防护

    func testPrivateAddressesAreNotQueryable() throws {
        let cases: [(String, Bool)] = [
            ("8.8.8.8", true),
            ("220.173.103.110", true),
            ("10.0.0.1", false),
            ("192.168.1.1", false),
            ("172.16.0.1", false),
            ("127.0.0.1", false),
            ("169.254.1.1", false),
            ("100.64.0.1", false),
            ("224.0.0.1", false),
            ("255.255.255.255", false),
            ("0.0.0.0", false)
        ]
        for (raw, queryable) in cases {
            let address = try XCTUnwrap(IPv4Math.Address.parse(raw))
            XCTAssertEqual(IPGeoService.isQueryable(address), queryable, raw)
        }
    }

    // MARK: - ipwho.is 解析

    func testParseIPWhoIs() throws {
        let json = """
        {
          "ip": "220.173.103.110",
          "success": true,
          "country": "China",
          "region": "Guangxi",
          "city": "Nanning",
          "timezone": {"id": "Asia/Shanghai"},
          "connection": {"asn": 4134, "org": "Chinanet", "isp": "China Telecom"}
        }
        """.data(using: .utf8)!

        let result = try IPGeoService.parseIPWhoIs(json)
        XCTAssertEqual(result.location, "China · Guangxi · Nanning")
        XCTAssertEqual(result.isp, "China Telecom")
        XCTAssertEqual(result.asn, "AS4134")
        XCTAssertEqual(result.timezone, "Asia/Shanghai")
        XCTAssertEqual(result.source, "ipwho.is")
    }

    func testParseIPWhoIsFailureFlag() throws {
        let json = """
        {"success": false, "message": "Invalid IP"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try IPGeoService.parseIPWhoIs(json))
    }

    func testParseIPWhoIsMissingIspFallsBack() throws {
        let json = """
        {"success": true, "country": "United States", "region": "California", "city": "Mountain View"}
        """.data(using: .utf8)!
        let result = try IPGeoService.parseIPWhoIs(json)
        XCTAssertEqual(result.location, "United States · California · Mountain View")
        XCTAssertEqual(result.isp, "未知")
        XCTAssertNil(result.asn)
    }

    // MARK: - ipinfo.io 解析

    func testParseIPInfo() throws {
        let json = """
        {"ip": "1.2.3.4", "city": "Shenzhen", "region": "Guangdong", "country": "CN", "org": "AS45090 Shenzhen Tencent Computer Systems Company Limited", "timezone": "Asia/Shanghai"}
        """.data(using: .utf8)!
        let result = try IPGeoService.parseIPInfo(json)
        XCTAssertEqual(result.location, "China · Guangdong · Shenzhen")
        XCTAssertEqual(result.isp, "AS45090 Shenzhen Tencent Computer Systems Company Limited")
        XCTAssertEqual(result.asn, "AS45090")
        XCTAssertEqual(result.timezone, "Asia/Shanghai")
        XCTAssertEqual(result.source, "ipinfo.io")
    }

    func testCountryCodeMapping() {
        XCTAssertEqual(IPGeoService.countryName("CN"), "China")
        XCTAssertEqual(IPGeoService.countryName("us"), "United States")
        XCTAssertEqual(IPGeoService.countryName("ZZ"), "ZZ")
    }
}
