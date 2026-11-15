import Foundation
import XCTest
@testable import LabTetherAgent

/// The protocol repo's local agent contract (`localagent/` at the commit in
/// `Fixtures/localagent/SOURCE.json`): ten real `/agent/status` bodies made
/// by the Go agent's own handler, and the closed code sets.
enum StatusFixtures {
    static let names = [
        "alerts-with-temperature",
        "auth-failed-enrollment-token-rejected",
        "auth-failed-token-rejected",
        "connected",
        "connected-token-persistence-failed",
        "connecting-transient-host-unreachable",
        "disconnected-no-transport",
        "enrollment-pending",
        "enrollment-refused-hub-words",
        "minimal-optional-fields-absent",
    ]

    static var root: URL {
        get throws {
            try XCTUnwrap(Bundle.module.url(forResource: "localagent", withExtension: nil), "contract copy missing")
        }
    }

    /// The file names on disk, so a fixture added to the copy is not skipped.
    static func namesOnDisk() throws -> [String] {
        let dir = try root.appendingPathComponent("fixtures/status")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("fixtures/status/\(name).json"))
    }

    /// A real body with one change, for a case no fixture covers.
    static func variant(_ name: String, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: data(name)) as? [String: Any])
        edit(&body)
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func codes() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("codes.v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
