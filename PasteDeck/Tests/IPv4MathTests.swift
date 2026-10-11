//
//  IPv4MathTests.swift
//
//  验证 IPv4 地址解析、地址类型判断与子网计算（含 /0、/31、/32 边界）。
//

import Foundation
import XCTest
@testable import PasteDeck

final class IPv4MathTests: XCTestCase {

    // MARK: - 地址解析

    func testParseAddress() {
        XCTAssertEqual(IPv4Math.Address.parse("220.173.103.110")?.value, 0xDCAD676E)
        XCTAssertEqual(IPv4Math.Address.parse("0.0.0.0")?.value, 0)
        XCTAssertEqual(IPv4Math.Address.parse("255.255.255.255")?.value, 0xFFFF_FFFF)
        // 允许前导零，并忽略首尾空白。
        XCTAssertEqual(IPv4Math.Address.parse(" 010.001.002.003 "), IPv4Math.Address.parse("10.1.2.3"))
    }

    func testRejectsInvalidAddress() {
        XCTAssertNil(IPv4Math.Address.parse("256.1.1.1"))
        XCTAssertNil(IPv4Math.Address.parse("1.2.3"))
        XCTAssertNil(IPv4Math.Address.parse("1.2.3.4.5"))
        XCTAssertNil(IPv4Math.Address.parse("a.b.c.d"))
        XCTAssertNil(IPv4Math.Address.parse("1.2.3."))
        XCTAssertNil(IPv4Math.Address.parse(".1.2.3"))
        XCTAssertNil(IPv4Math.Address.parse("1..2.3"))
        XCTAssertNil(IPv4Math.Address.parse("1234.1.1.1"))
        XCTAssertNil(IPv4Math.Address.parse(""))
        XCTAssertNil(IPv4Math.Address.parse(nil))
    }

    func testDottedStringRoundTrip() {
        let address = IPv4Math.Address.parse("220.173.103.110")
        XCTAssertEqual(address?.dottedString, "220.173.103.110")
        XCTAssertEqual(IPv4Math.Address(value: 0x0A00_0001).dottedString, "10.0.0.1")
    }

    // MARK: - 地址类型

    func testAddressKinds() {
        func kind(_ raw: String) -> IPv4Math.AddressKind {
            IPv4Math.kind(of: IPv4Math.Address.parse(raw)!)
        }

        XCTAssertEqual(kind("0.0.0.0"), .unspecified)
        XCTAssertEqual(kind("127.0.0.1"), .loopback)
        XCTAssertEqual(kind("10.1.2.3"), .privateNetwork)
        XCTAssertEqual(kind("172.16.0.1"), .privateNetwork)
        XCTAssertEqual(kind("172.31.255.255"), .privateNetwork)
        XCTAssertEqual(kind("172.32.0.1"), .publicAddress)
        XCTAssertEqual(kind("192.168.1.1"), .privateNetwork)
        XCTAssertEqual(kind("169.254.10.10"), .linkLocal)
        XCTAssertEqual(kind("100.64.0.1"), .carrierGradeNAT)
        XCTAssertEqual(kind("100.127.255.254"), .carrierGradeNAT)
        XCTAssertEqual(kind("100.128.0.1"), .publicAddress)
        XCTAssertEqual(kind("224.0.0.1"), .multicast)
        XCTAssertEqual(kind("239.255.255.255"), .multicast)
        XCTAssertEqual(kind("240.0.0.1"), .reserved)
        XCTAssertEqual(kind("255.255.255.255"), .reserved)
        XCTAssertEqual(kind("8.8.8.8"), .publicAddress)
        XCTAssertEqual(kind("220.173.103.110"), .publicAddress)
    }

    // MARK: - 子网计算

    func testSubnet24() {
        let parsed = IPv4Math.parseSubnet("192.168.1.100/24")
        let subnet = parsed?.subnet
        XCTAssertEqual(subnet?.network.dottedString, "192.168.1.0")
        XCTAssertEqual(subnet?.broadcast.dottedString, "192.168.1.255")
        XCTAssertEqual(subnet?.mask.dottedString, "255.255.255.0")
        XCTAssertEqual(subnet?.wildcardMask.dottedString, "0.0.0.255")
        XCTAssertEqual(subnet?.totalAddressCount, 256)
        XCTAssertEqual(subnet?.usableAddressCount, 254)
        XCTAssertEqual(subnet?.firstUsable.dottedString, "192.168.1.1")
        XCTAssertEqual(subnet?.lastUsable.dottedString, "192.168.1.254")
        XCTAssertEqual(subnet?.isSingleHost, false)
    }

    func testSubnetInputAddressNormalized() {
        let parsed = IPv4Math.parseSubnet("10.9.130.77/8")
        XCTAssertEqual(parsed?.subnet.network.dottedString, "10.0.0.0")
        XCTAssertEqual(parsed?.subnet.broadcast.dottedString, "10.255.255.255")
    }

    func testSubnet31PointToPoint() {
        let parsed = IPv4Math.parseSubnet("10.0.0.4/31")
        let subnet = parsed?.subnet
        XCTAssertEqual(subnet?.network.dottedString, "10.0.0.4")
        XCTAssertEqual(subnet?.broadcast.dottedString, "10.0.0.5")
        XCTAssertEqual(subnet?.usableAddressCount, 2)
        XCTAssertEqual(subnet?.firstUsable.dottedString, "10.0.0.4")
        XCTAssertEqual(subnet?.lastUsable.dottedString, "10.0.0.5")
    }

    func testSubnet32SingleHost() {
        let parsed = IPv4Math.parseSubnet("8.8.8.8/32")
        let subnet = parsed?.subnet
        XCTAssertEqual(subnet?.network.dottedString, "8.8.8.8")
        XCTAssertEqual(subnet?.broadcast.dottedString, "8.8.8.8")
        XCTAssertEqual(subnet?.totalAddressCount, 1)
        XCTAssertEqual(subnet?.usableAddressCount, 1)
        XCTAssertEqual(subnet?.firstUsable.dottedString, "8.8.8.8")
        XCTAssertEqual(subnet?.lastUsable.dottedString, "8.8.8.8")
        XCTAssertEqual(subnet?.isSingleHost, true)
    }

    func testSubnet0WholeInternet() {
        let parsed = IPv4Math.parseSubnet("1.2.3.4/0")
        let subnet = parsed?.subnet
        XCTAssertEqual(subnet?.network.dottedString, "0.0.0.0")
        XCTAssertEqual(subnet?.broadcast.dottedString, "255.255.255.255")
        XCTAssertEqual(subnet?.mask.dottedString, "0.0.0.0")
        XCTAssertEqual(subnet?.totalAddressCount, 4_294_967_296)
        XCTAssertEqual(subnet?.usableAddressCount, 4_294_967_294)
        XCTAssertEqual(subnet?.firstUsable.dottedString, "0.0.0.1")
        XCTAssertEqual(subnet?.lastUsable.dottedString, "255.255.255.254")
    }

    func testBareAddressTreatedAsHost32() {
        let parsed = IPv4Math.parseSubnet("220.173.103.110")
        XCTAssertEqual(parsed?.subnet.prefixLength, 32)
        XCTAssertEqual(parsed?.subnet.network.dottedString, "220.173.103.110")
    }

    func testRejectsInvalidCIDR() {
        XCTAssertNil(IPv4Math.parseSubnet("1.2.3.4/33"))
        XCTAssertNil(IPv4Math.parseSubnet("1.2.3.4/-1"))
        XCTAssertNil(IPv4Math.parseSubnet("1.2.3.4/"))
        XCTAssertNil(IPv4Math.parseSubnet("1.2.3.4/abc"))
        XCTAssertNil(IPv4Math.parseSubnet("1.2.3.4/24/8"))
        XCTAssertNil(IPv4Math.parseSubnet("abc/24"))
        XCTAssertNil(IPv4Math.parseSubnet(""))
        XCTAssertNil(IPv4Math.parseSubnet(nil))
    }
}
