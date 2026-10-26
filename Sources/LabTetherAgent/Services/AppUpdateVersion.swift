import Foundation

/// A strict `major.minor.patch[-prerelease][+build]` version, as used by the
/// signed app's CFBundleShortVersionString and the release tags (`v1.7.0`).
struct AppVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    /// Non-nil for prereleases such as `1.7.0-rc.1`, which sort before `1.7.0`.
    let prerelease: String?

    init?(_ raw: String) {
        var text = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        if let plus = text.firstIndex(of: "+") { text = text[..<plus] }
        var prerelease: String?
        if let dash = text.firstIndex(of: "-") {
            let suffix = text[text.index(after: dash)...]
            guard !suffix.isEmpty else { return nil }
            prerelease = String(suffix)
            text = text[..<dash]
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        self.prerelease = prerelease
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, .some): return false
        case (.some, nil): return true
        case let (.some(left), .some(right)):
            return left.compare(right, options: .numeric) == .orderedAscending
        }
    }

    /// Display form without a `v` prefix or build metadata, e.g. `1.7.0`.
    var displayString: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }

    /// True only when both strings parse and `candidate` is strictly newer.
    /// Development builds report "dev" and therefore never see an update.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = AppVersion(candidate), let current = AppVersion(current) else { return false }
        return candidate > current
    }
}

/// The newest published, non-prerelease macOS app release.
struct AppUpdateRelease: Equatable {
    static let fallbackPage = URL(string: "https://github.com/labtether/labtether-mac/releases/latest")!

    let version: String
    let pageURL: URL

    /// Parses GitHub's `releases/latest` response. Drafts, prereleases,
    /// malformed tags and non-GitHub pages are ignored or replaced so the
    /// menu can only ever open the official release page.
    static func parse(_ data: Data) -> AppUpdateRelease? {
        struct Payload: Decodable {
            let tagName: String?
            let htmlURL: String?
            let draft: Bool?
            let prerelease: Bool?

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
                case draft, prerelease
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let tag = payload.tagName, let version = AppVersion(tag),
              version.prerelease == nil else { return nil }
        let page = trustedPage(payload.htmlURL.flatMap { URL(string: $0) })
        return AppUpdateRelease(version: version.displayString, pageURL: page)
    }

    /// Only this repository's GitHub release pages may be opened.
    static func trustedPage(_ url: URL?) -> URL {
        guard let url, url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/labtether/labtether-mac/releases/") else { return fallbackPage }
        return url
    }
}
