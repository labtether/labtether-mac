import XCTest
@testable import LabTetherAgent

final class ConsoleURLBuilderTests: XCTestCase {
    func testNodeURLPreservesBasePathAndEscapesAssetIDSegment() {
        let base = URL(string: "https://hub.example.com/console/")!
        let url = ConsoleURLBuilder.nodeURL(base: base, assetID: "asset/one?panel#cpu%25")

        XCTAssertEqual(
            url?.absoluteString,
            "https://hub.example.com/console/nodes/asset%2Fone%3Fpanel%23cpu%2525"
        )
    }

    func testNodeURLDropsBaseQueryAndFragment() {
        let base = URL(string: "https://hub.example.com/root?tab=old#frag")!
        let url = ConsoleURLBuilder.nodeURL(base: base, assetID: "node-1")

        XCTAssertEqual(url?.absoluteString, "https://hub.example.com/root/nodes/node-1")
    }

    func testNodeURLRejectsBlankAssetID() {
        let base = URL(string: "https://hub.example.com")!

        XCTAssertNil(ConsoleURLBuilder.nodeURL(base: base, assetID: "  "))
    }
}
