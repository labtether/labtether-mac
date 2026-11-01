import Foundation
import Security

extension AgentSettings {
    func loadSecretsFromKeychain() {
        isLoadingSecrets = true
        apiToken = bootstrapSecrets.load(account: Self.apiTokenAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        enrollmentToken = bootstrapSecrets.load(account: Self.enrollmentTokenAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        webrtcTurnPass = bootstrapSecrets.load(account: Self.webrtcTurnPassAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isLoadingSecrets = false
    }

    func persistSecret(_ rawValue: String, account: String) {
        if isLoadingSecrets {
            return
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let issueKey = keychainIssueKey(for: account)
        if value.isEmpty {
            let status = bootstrapSecrets.deleteStatus(account: account)
            if status == errSecSuccess {
                setSecretPersistenceIssue(key: issueKey, message: nil)
                synchronizeRuntimeSecretFilesAfterSecretChange(account: account)
            } else {
                setSecretPersistenceIssue(
                    key: issueKey,
                    message: "\(secretLabel(for: account)) could not be removed from the macOS Keychain: \(KeychainSecretStore.errorMessage(for: status))"
                )
            }
            return
        }
        let status = bootstrapSecrets.saveStatus(value, account: account)
        if status == errSecSuccess {
            setSecretPersistenceIssue(key: issueKey, message: nil)
            if account == Self.apiTokenAccount || account == Self.enrollmentTokenAccount {
                unbindTypedToken()
            }
        } else {
            setSecretPersistenceIssue(
                key: issueKey,
                message: "\(secretLabel(for: account)) could not be saved to the macOS Keychain: \(KeychainSecretStore.errorMessage(for: status))"
            )
        }
    }

    func mergedExecutablePath() -> String {
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Applications/Tailscale.app/Contents/MacOS",
        ]

        var combined: [String] = []
        if let inherited = ProcessInfo.processInfo.environment["PATH"] {
            combined.append(contentsOf: inherited.split(separator: ":").map(String.init))
        }
        combined.append(contentsOf: defaults)

        var seen = Set<String>()
        let deduped = combined.filter { part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if seen.contains(trimmed) { return false }
            seen.insert(trimmed)
            return true
        }
        return deduped.joined(separator: ":")
    }

    func cleanupEphemeralSecrets() {
        try? removeRuntimeSecretIfNeeded(
            at: localAPIAuthTokenFilePath,
            issueKey: "runtime.localAPIAuthToken",
            label: "Local API auth token"
        )
        localAPIAuthToken = ""
    }

    /// Remove a one-use enrollment secret after the Go child has either issued
    /// or loaded the durable agent credential. This deliberately preserves the
    /// agent token file so an enrolled app can reconnect after relaunch.
    func clearConsumedEnrollmentTokenPreservingAgentToken() {
        guard !enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
              (stateLocation?.isolated == true && hasPersistedEnrollmentToken) else {
            return
        }

        let status = bootstrapSecrets.deleteStatus(account: Self.enrollmentTokenAccount)
        guard status == errSecSuccess else {
            setSecretPersistenceIssue(
                key: keychainIssueKey(for: Self.enrollmentTokenAccount),
                message: "Enrollment token could not be removed from the macOS Keychain: \(KeychainSecretStore.errorMessage(for: status))"
            )
            return
        }

        isLoadingSecrets = true
        enrollmentToken = ""
        isLoadingSecrets = false
        setSecretPersistenceIssue(key: keychainIssueKey(for: Self.enrollmentTokenAccount), message: nil)
        try? removeRuntimeSecretIfNeeded(
            at: enrollmentTokenFilePath,
            issueKey: "runtime.enrollmentToken",
            label: "Enrollment token"
        )
    }

    func synchronizeRuntimeSecretFilesAfterSecretChange(account: String) {
        switch account {
        case Self.apiTokenAccount:
            if Self.runtimeAPITokenFileAction(
                apiToken: apiToken,
                enrollmentToken: enrollmentToken,
                hasPersistedAgentToken: hasPersistedAgentToken
            ) == .remove {
                try? removeRuntimeSecretIfNeeded(
                    at: tokenFilePath,
                    issueKey: "runtime.apiToken",
                    label: "API token"
                )
            }
        case Self.enrollmentTokenAccount:
            try? removeRuntimeSecretIfNeeded(
                at: enrollmentTokenFilePath,
                issueKey: "runtime.enrollmentToken",
                label: "Enrollment token"
            )
        case Self.webrtcTurnPassAccount:
            try? removeRuntimeSecretIfNeeded(
                at: webrtcTurnPassFilePath,
                issueKey: "runtime.turnPass",
                label: "WebRTC TURN password"
            )
        default:
            break
        }
    }

    func persistRuntimeSecret(_ value: String, to path: String, issueKey: String, label: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let parent = fileURL.deletingLastPathComponent()
        do {
            if let stateLocation {
                let name = try stateLocation.ownedName(for: path)
                try stateLocation.write(Data((value + "\n").utf8), name: name)
            } else {
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
                try (value + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
            setSecretPersistenceIssue(key: issueKey, message: nil)
        } catch {
            let message = "\(label) could not be written to \(path): \(error.localizedDescription)"
            setSecretPersistenceIssue(key: issueKey, message: message)
            throw AgentSettingsSecretError(message: message)
        }
    }

    func removeRuntimeSecretIfNeeded(at path: String, issueKey: String, label: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            setSecretPersistenceIssue(key: issueKey, message: nil)
            return
        }
        do {
            if let stateLocation {
                try stateLocation.remove(stateLocation.ownedName(for: path))
            } else {
                try FileManager.default.removeItem(atPath: path)
            }
            setSecretPersistenceIssue(key: issueKey, message: nil)
        } catch {
            let message = "\(label) could not be removed from \(path): \(error.localizedDescription)"
            setSecretPersistenceIssue(key: issueKey, message: message)
            throw AgentSettingsSecretError(message: message)
        }
    }

    func ensureLocalAPIAuthToken() throws -> String {
        if localAPIAuthToken.isEmpty {
            localAPIAuthToken = generateLocalAPIAuthToken()
        }
        try persistRuntimeSecret(
            localAPIAuthToken,
            to: localAPIAuthTokenFilePath,
            issueKey: "runtime.localAPIAuthToken",
            label: "Local API auth token"
        )
        return localAPIAuthTokenFilePath
    }

    func generateLocalAPIAuthToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    func keychainIssueKey(for account: String) -> String {
        "keychain.\(account)"
    }

    func secretLabel(for account: String) -> String {
        switch account {
        case Self.apiTokenAccount:
            return "API token"
        case Self.enrollmentTokenAccount:
            return "Enrollment token"
        case Self.webrtcTurnPassAccount:
            return "WebRTC TURN password"
        default:
            return "Secret"
        }
    }

    func setSecretPersistenceIssue(key: String, message: String?) {
        if let message, !message.isEmpty {
            secretPersistenceIssueMap[key] = message
        } else {
            secretPersistenceIssueMap.removeValue(forKey: key)
        }
        secretPersistenceErrors = secretPersistenceIssueMap.keys.sorted().compactMap { secretPersistenceIssueMap[$0] }
    }
}
