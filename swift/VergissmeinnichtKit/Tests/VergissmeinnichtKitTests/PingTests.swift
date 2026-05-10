import XCTest
@testable import VergissmeinnichtKit

final class PingTests: XCTestCase {
    func testPingReturnsPong() {
        XCTAssertEqual(ping(), "pong")
    }
}
