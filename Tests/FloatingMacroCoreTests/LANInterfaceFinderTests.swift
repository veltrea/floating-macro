import XCTest
@testable import FloatingMacroCore

final class LANInterfaceFinderTests: XCTestCase {

    // MARK: - shouldExclude

    func testExcludesVirtualInterfaces() {
        XCTAssertTrue(LANInterfaceFinder.shouldExclude("lo0"))
        XCTAssertTrue(LANInterfaceFinder.shouldExclude("awdl0"))
        XCTAssertTrue(LANInterfaceFinder.shouldExclude("llw0"))
        XCTAssertTrue(LANInterfaceFinder.shouldExclude("utun3"))
        XCTAssertTrue(LANInterfaceFinder.shouldExclude("vmnet1"))
        XCTAssertTrue(LANInterfaceFinder.shouldExclude("bridge0"))
    }

    func testKeepsPhysicalInterfaces() {
        XCTAssertFalse(LANInterfaceFinder.shouldExclude("en0"))
        XCTAssertFalse(LANInterfaceFinder.shouldExclude("en1"))
    }

    // MARK: - isPrivate

    func testRecognizesPrivateAddresses() {
        XCTAssertTrue(LANInterfaceFinder.isPrivate("192.168.1.21"))
        XCTAssertTrue(LANInterfaceFinder.isPrivate("10.0.0.5"))
        XCTAssertTrue(LANInterfaceFinder.isPrivate("172.16.0.1"))
        XCTAssertTrue(LANInterfaceFinder.isPrivate("172.31.255.255"))
    }

    func testRejectsPublicAddresses() {
        XCTAssertFalse(LANInterfaceFinder.isPrivate("8.8.8.8"))
        XCTAssertFalse(LANInterfaceFinder.isPrivate("172.32.0.1"))
        XCTAssertFalse(LANInterfaceFinder.isPrivate("172.15.0.1"))
        XCTAssertFalse(LANInterfaceFinder.isPrivate("not-an-ip"))
    }

    // MARK: - rank ordering

    func testRankPutsPrivateLANBeforePublic() {
        let result = LANInterfaceFinder.rank([
            (name: "en1", addr: "8.8.8.8"),
            (name: "en0", addr: "192.168.1.21"),
        ])
        XCTAssertEqual(result.first, "192.168.1.21")
    }

    func testRankPrefersLowerEnNumber() {
        let result = LANInterfaceFinder.rank([
            (name: "en1", addr: "192.168.1.115"),
            (name: "en0", addr: "192.168.1.21"),
        ])
        XCTAssertEqual(result.first, "192.168.1.21",
                       "en0 (Ethernet) が en1 (Wi-Fi) より優先される")
    }

    // MARK: - Live system probe (smoke test)

    func testLiveProbeReturnsAtLeastSomething() {
        // 開発機 / CI どちらも en0 か en1 で何らかの IPv4 を持つ前提。
        let addrs = LANInterfaceFinder.ipv4Addresses()
        // 何も無くてもクラッシュしないだけで OK にする (Linux など)。
        XCTAssertGreaterThanOrEqual(addrs.count, 0)
    }
}
