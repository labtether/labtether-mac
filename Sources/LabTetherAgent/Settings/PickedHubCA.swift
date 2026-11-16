import Foundation

/// The Hub CA file in the Mac App Store edition.
///
/// The App Sandbox lets the app read a file the person picks in the file
/// panel, and only while the app runs. The agent is a child with the app's
/// static rights, so it can read nothing outside the app's container. So:
///
/// - a picked file is read at once, checked against the Hub exactly as a
///   typed file is (`chooseCAFile`), and kept as a copy in the state folder,
///   which is the file the agent is given;
/// - a security-scoped bookmark to the picked file is kept as well. Before
///   each start the copy follows the file: a changed file replaces the copy
///   and a removed file removes it, so the rules in `ChosenHubCA.swift` (a
///   verified CA that changed or went missing stops the agent until it is
///   checked again) work as they do in the Developer ID edition;
/// - a file that does not verify the Hub never replaces a working copy.
extension AgentSettings {
    static let pickedCACopyName = "picked-hub-ca.pem"
    static let pickedCAStagingName = "picked-hub-ca.new.pem"
    static let pickedCABookmarkRecord = "pickedCABookmark"
    static let pickedCAOriginalRecord = "pickedCAOriginalPath"
    static let pickedCASaveFailedMessage = "The CA certificate could not be saved in LabTether's folder."
    static let pickedCARemovedLine = "The CA certificate file chosen in Settings › Security is gone, so LabTether's copy was removed."
    static let pickedCAChangedLine = "The CA certificate file chosen in Settings › Security changed, so LabTether's copy was updated."

    var pickedCACopyPath: String {
        appSupportDirectory.appendingPathComponent(Self.pickedCACopyName).path
    }

    private var pickedCAStagingPath: String {
        appSupportDirectory.appendingPathComponent(Self.pickedCAStagingName).path
    }

    /// Where the picked file was, for Settings; empty when none is in use.
    var pickedCAOriginalPath: String {
        tlsCAFile == pickedCACopyPath ? storedRecord(Self.pickedCAOriginalRecord) : ""
    }

    /// The person picked `url` in the file panel. Returns nil when it is
    /// saved, else the words why not; the previous setting then stays.
    @MainActor
    func choosePickedCAFile(_ url: URL, check: ChosenCACheck = HubCATrust.verifiesAlone) async -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = Self.caFileData(at: url) else { return Self.chosenCAUnusableMessage }
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil
        )
        // Checked under its own name, so a refused file never touches the copy in use.
        do { try writeChildFile(data, name: Self.pickedCAStagingName) } catch { return Self.pickedCASaveFailedMessage }
        defer { _ = try? removeChildFile(Self.pickedCAStagingName) }
        let previous = tlsCAFile
        if let words = await chooseCAFile(pickedCAStagingPath, check: check) { return words }
        do { try writeChildFile(data, name: Self.pickedCACopyName) } catch {
            tlsCAFile = previous
            return Self.pickedCASaveFailedMessage
        }
        tlsCAFile = pickedCACopyPath
        setStoredRecord(bookmark?.base64EncodedString() ?? "", key: Self.pickedCABookmarkRecord)
        setStoredRecord(url.path, key: Self.pickedCAOriginalRecord)
        objectWillChange.send()
        return nil
    }

    /// "Remove": no CA file, no copy, no bookmark.
    @MainActor
    func removePickedCAFile() async {
        _ = await chooseCAFile("")
        _ = try? removeChildFile(Self.pickedCACopyName)
        setStoredRecord("", key: Self.pickedCABookmarkRecord)
        setStoredRecord("", key: Self.pickedCAOriginalRecord)
        objectWillChange.send()
    }

    /// Before each start: the copy follows the picked file. Returns one line
    /// for the log when the copy changed. A bookmark that cannot be resolved
    /// for any reason but a missing file keeps the copy as it is.
    @discardableResult
    func refreshPickedCACopy() -> String? {
        guard tlsCAFile == pickedCACopyPath,
              let bookmark = Data(base64Encoded: storedRecord(Self.pickedCABookmarkRecord)), !bookmark.isEmpty else { return nil }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            guard (error as NSError).domain == NSCocoaErrorDomain,
                  (error as NSError).code == NSFileNoSuchFileError else { return nil }
            return removePickedCACopy()
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { return removePickedCACopy() }
        guard let data = Self.caFileData(at: url) else { return nil }
        if stale, let fresh = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            setStoredRecord(fresh.base64EncodedString(), key: Self.pickedCABookmarkRecord)
        }
        guard FileManager.default.contents(atPath: pickedCACopyPath) != data else { return nil }
        do { try writeChildFile(data, name: Self.pickedCACopyName) } catch { return nil }
        objectWillChange.send()
        return Self.pickedCAChangedLine
    }

    private func removePickedCACopy() -> String? {
        guard (try? removeChildFile(Self.pickedCACopyName)) == true else { return nil }
        objectWillChange.send()
        return Self.pickedCARemovedLine
    }

    /// The file's bytes when it holds at least one PEM certificate.
    static func caFileData(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count <= 1_048_576,
              let text = String(data: data, encoding: .utf8),
              !HubCATrust.certificates(fromPEM: text).isEmpty else { return nil }
        return data
    }
}
