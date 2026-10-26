import XCTest
@testable import LabTetherAgent

/// The update menu item must appear only for a genuinely newer stable release.
/// A plain string or Double comparison would call 1.10.0 older than 1.9.0.
final class AppUpdateVersionTests: XCTestCase {
    func testNumericComponentsCompareAsNumbers() {
        XCTAssertTrue(AppVersion.isNewer("1.10.0", than: "1.7.0"))
        XCTAssertTrue(AppVersion.isNewer("v1.7.1", than: "1.7.0"))
        XCTAssertTrue(AppVersion.isNewer("2.0", than: "1.99.99"))
        XCTAssertFalse(AppVersion.isNewer("1.7.0", than: "1.10.0"))
        XCTAssertFalse(AppVersion.isNewer("v1.7.0", than: "1.7.0"))
        XCTAssertFalse(AppVersion.isNewer("1.7.0+build.9", than: "1.7.0"))
    }

    func testPrereleaseSortsBeforeItsRelease() {
        XCTAssertTrue(AppVersion.isNewer("1.7.0", than: "1.7.0-rc.1"))
        XCTAssertFalse(AppVersion.isNewer("1.7.0-rc.1", than: "1.7.0"))
        XCTAssertTrue(AppVersion.isNewer("1.7.0-rc.10", than: "1.7.0-rc.9"))
    }

    func testMalformedOrDevelopmentVersionsNeverOfferAnUpdate() {
        for malformed in ["", "dev", "v", "1..0", "1.2.3.4", "1.2.x", "1.2.3-", "１.２.３", "99999999999999999999.0.0"] {
            XCTAssertNil(AppVersion(malformed), malformed)
            XCTAssertFalse(AppVersion.isNewer(malformed, than: "1.7.0"), malformed)
            XCTAssertFalse(AppVersion.isNewer("9.9.9", than: malformed), malformed)
        }
    }

    func testReleaseParsingIgnoresPrereleasesAndKeepsOnlyOfficialPages() throws {
        func release(_ fields: String) -> AppUpdateRelease? {
            AppUpdateRelease.parse(Data("{\(fields)}".utf8))
        }
        let official = "https://github.com/labtether/labtether-mac/releases/tag/v1.8.0"
        let stable = try XCTUnwrap(release(#""tag_name":"v1.8.0","html_url":"\#(official)","draft":false,"prerelease":false"#))
        XCTAssertEqual(stable, AppUpdateRelease(version: "1.8.0", pageURL: URL(string: official)!))

        XCTAssertNil(release(#""tag_name":"v1.8.0","prerelease":true"#))
        XCTAssertNil(release(#""tag_name":"v1.8.0","draft":true"#))
        XCTAssertNil(release(#""tag_name":"v1.8.0-beta.1""#))
        XCTAssertNil(release(#""tag_name":"latest""#))

        let foreign = try XCTUnwrap(release(#""tag_name":"v1.8.0","html_url":"https://example.com/labtether""#))
        XCTAssertEqual(foreign.pageURL, AppUpdateRelease.fallbackPage)
    }
}
