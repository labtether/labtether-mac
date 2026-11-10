import Foundation

/// Which Hub an enrollment token file was made for.
///
/// The bundled agent sends the token in `enrollment-token` to whichever Hub it
/// is started against. A token typed in the app is tied to the Hub it was
/// typed for and is dropped when the address changes. A file that an installer
/// or a script put there had no such tie: after a change of address the agent
/// sent that token to the new Hub.
///
/// The tie is a small file beside the token, `enrollment-token.hub`, written
/// by whoever writes the token:
///
///     {"hub_url": "wss://hub.example.com:8443", "ca_fingerprint_sha256": "64 hex characters"}
///
/// `ca_fingerprint_sha256` is optional. A token file is sent only to the Hub
/// its tie names and, when the tie has a fingerprint, only when the CA the
/// agent trusts for that Hub has it. Without a tie, or with a tie for another
/// Hub, the token stays on disk unsent and setup asks for one.
extension AgentSettings {
    static let enrollmentTokenTieName = "enrollment-token.hub"

    struct EnrollmentTokenTie: Codable, Equatable {
        var hubURL: String
        var caFingerprint: String?

        enum CodingKeys: String, CodingKey {
            case hubURL = "hub_url"
            case caFingerprint = "ca_fingerprint_sha256"
        }
    }

    enum EnrollmentTokenFile: Equatable {
        /// No token file.
        case none
        /// Made for the Hub in use: the agent may send it.
        case tied
        /// No tie, or a tie for another Hub or another CA: never sent.
        case untied
    }

    static let untiedEnrollmentTokenMessage =
        "The enrollment token saved on this Mac is not for this Hub. Add an enrollment token from this Hub."

    var enrollmentTokenFile: EnrollmentTokenFile {
        guard hasPersistedEnrollmentToken else { return .none }
        guard let tie = enrollmentTokenTie, let scope = pendingHubScope,
              let tiedURL = AgentSettingsNormalization.canonicalHubWebSocketURL(from: tie.hubURL),
              Self.credentialScope(forHubWebSocketURL: tiedURL) == scope else { return .untied }
        let wanted = (tie.caFingerprint ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !wanted.isEmpty {
            guard case .file(let path) = hubCAPin, Self.firstFingerprint(inPEMFile: path) == wanted else { return .untied }
        }
        return .tied
    }

    /// The CA fingerprint the token file's tie names, when that tie is for the Hub at `hubURL`.
    func enrollmentTokenTieCA(forHubURL hubURL: String) -> String? {
        guard hasPersistedEnrollmentToken, let tie = enrollmentTokenTie,
              let wanted = tie.caFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !wanted.isEmpty,
              let url = AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL),
              let tiedURL = AgentSettingsNormalization.canonicalHubWebSocketURL(from: tie.hubURL),
              Self.credentialScope(forHubWebSocketURL: tiedURL) == Self.credentialScope(forHubWebSocketURL: url) else { return nil }
        return wanted
    }

    var enrollmentTokenTie: EnrollmentTokenTie? {
        let data: Data?
        if let stateLocation {
            data = try? stateLocation.read(Self.enrollmentTokenTieName, maximum: 4_096)
        } else {
            let path = appSupportDirectory.appendingPathComponent(Self.enrollmentTokenTieName).path
            data = FileManager.default.contents(atPath: path).flatMap { $0.count <= 4_096 ? $0 : nil }
        }
        return data.flatMap { try? JSONDecoder().decode(EnrollmentTokenTie.self, from: $0) }
    }

    /// The app wrote the token file itself, from a token typed for the Hub in use.
    func tieEnrollmentTokenToCurrentHub() throws {
        guard let url = normalizedHubWebSocketURL() else { return }
        let data = try JSONEncoder().encode(EnrollmentTokenTie(hubURL: url, caFingerprint: nil))
        if let stateLocation {
            _ = try? stateLocation.removeRegularFile(Self.enrollmentTokenTieName)
            try stateLocation.write(data, name: Self.enrollmentTokenTieName)
        } else {
            let file = appSupportDirectory.appendingPathComponent(Self.enrollmentTokenTieName)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    /// Goes with the token file whenever the app removes that.
    func removeEnrollmentTokenTie() {
        _ = try? removeChildFile(Self.enrollmentTokenTieName)
    }
}
