import Foundation
import Darwin

/// The root and lock are acquired before preferences, credentials or app services.
final class AppStateLocation {
    enum Failure: Error { case invalidRoot, busy, unsafeFile, io }
    static let current: AppStateLocation = {
        do { return try bootstrap(arguments: ProcessInfo.processInfo.arguments) }
        catch {
            fputs("LabTether: state directory unavailable or already in use.\n", stderr)
            exit(78)
        }
    }()

    let root: URL
    let isolated: Bool
    let device: dev_t
    let inode: ino_t
    private let directoryFD: Int32
    private let lockFD: Int32

    static func bootstrap(arguments: [String]) throws -> AppStateLocation {
        guard !arguments.contains(where: { $0.hasPrefix("--state-directory") && $0 != "--state-directory" }) else {
            throw Failure.invalidRoot
        }
        let indices = arguments.indices.filter { arguments[$0] == "--state-directory" }
        guard indices.count <= 1 else { throw Failure.invalidRoot }
        if let index = indices.first {
            guard index + 1 < arguments.count, arguments[index + 1].hasPrefix("/") else { throw Failure.invalidRoot }
            return try AppStateLocation(root: URL(fileURLWithPath: arguments[index + 1]), isolated: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("LabTether")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return try AppStateLocation(root: root.resolvingSymlinksInPath(), isolated: false)
    }

    init(root: URL, isolated: Bool) throws {
        guard root.path.hasPrefix("/"), root.path == root.standardizedFileURL.path,
              root.path == root.resolvingSymlinksInPath().path else { throw Failure.invalidRoot }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.invalidRoot }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else {
            close(fd); throw Failure.invalidRoot
        }
        let held = openat(fd, ".app.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard held >= 0 else { close(fd); throw Failure.unsafeFile }
        var lockInfo = stat()
        guard fstat(held, &lockInfo) == 0, Self.privateFile(lockInfo), flock(held, LOCK_EX | LOCK_NB) == 0 else {
            close(held); close(fd); throw Failure.busy
        }
        self.root = root
        self.isolated = isolated
        device = info.st_dev
        inode = info.st_ino
        directoryFD = fd
        lockFD = held
        if isolated { try validateRuntimeFiles() }
    }

    deinit { close(lockFD); close(directoryFD) }

    func validate() throws {
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_dev == device, info.st_ino == inode,
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700,
              info.st_uid == getuid() else { throw Failure.invalidRoot }
        var lockInfo = stat(), held = stat()
        guard fstatat(directoryFD, ".app.lock", &lockInfo, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(lockFD, &held) == 0, lockInfo.st_dev == held.st_dev,
              lockInfo.st_ino == held.st_ino, Self.privateFile(lockInfo) else { throw Failure.busy }
    }

    func read(_ name: String, maximum: Int = 65_536) throws -> Data? {
        try validateName(name)
        guard maximum > 0, maximum <= 8 * 1024 * 1024 else { throw Failure.unsafeFile }
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw Failure.unsafeFile }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, Self.privateFile(info), info.st_size <= maximum else { throw Failure.unsafeFile }
        var bytes = [UInt8](repeating: 0, count: maximum + 1)
        var count = 0
        let capacity = bytes.count
        while count < capacity {
            let amount = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: count), capacity - count) }
            if amount < 0 { if errno == EINTR { continue }; throw Failure.io }
            if amount == 0 { break }
            count += amount
        }
        guard count <= maximum else { throw Failure.unsafeFile }
        return Data(bytes.prefix(count))
    }

    func write(_ data: Data, name: String, maximum: Int = 65_536) throws {
        try validateName(name)
        guard maximum <= 8 * 1024 * 1024, data.count <= maximum else { throw Failure.unsafeFile }
        _ = try read(name, maximum: maximum)
        let temporary = ".write-" + UUID().uuidString
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.io }
        defer { close(fd); unlinkat(directoryFD, temporary, 0) }
        try data.withUnsafeBytes { buffer in
            var count = 0
            while count < buffer.count {
                let amount = Darwin.write(fd, buffer.baseAddress!.advanced(by: count), buffer.count - count)
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { throw Failure.io }
                count += amount
            }
        }
        guard fsync(fd) == 0 else { throw Failure.io }
        try validate()
        guard renameat(directoryFD, temporary, directoryFD, name) == 0 else { throw Failure.io }
    }

    func remove(_ name: String, maximum: Int = 65_536) throws {
        try validateName(name)
        guard try read(name, maximum: maximum) != nil else { return }
        guard unlinkat(directoryFD, name, 0) == 0 else { throw Failure.io }
    }

    /// Removes a regular file this user owns, whatever its mode. The Go child
    /// writes the Hub CA as 0644, which `remove` refuses. Returns false when
    /// the file does not exist.
    @discardableResult
    func removeRegularFile(_ name: String) throws -> Bool {
        try validateName(name)
        var info = stat()
        guard fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return false }
            throw Failure.io
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 else {
            throw Failure.unsafeFile
        }
        guard unlinkat(directoryFD, name, 0) == 0 else { throw Failure.io }
        return true
    }

    /// URL directory hints are not file ownership. Keep exact path spelling,
    /// then perform the actual access through this already-held directory FD.
    func ownedName(for path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard path.hasPrefix("/"), url.path == path,
              url.standardizedFileURL.path == path,
              url.deletingLastPathComponent().path == root.path else {
            throw Failure.unsafeFile
        }
        let name = url.lastPathComponent
        try validateName(name)
        return name
    }

    func validateRuntimeFiles() throws {
        try validate()
        for name in ["agent-token", "enrollment-token", "webrtc-turn-pass", "local-api-auth-token",
                     "agent-config.json", "device-key", "device-key.pub", "device-fingerprint",
                     "session-history.json", "bandwidth-history.json"] {
            var info = stat()
            let result = fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW)
            if result < 0 && errno == ENOENT { continue }
            guard result == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
                  info.st_nlink == 1, info.st_mode & 0o022 == 0 else { throw Failure.unsafeFile }
        }
    }

    private func validateName(_ name: String) throws {
        try validate()
        guard !name.isEmpty, !name.contains("/"), name != ".", name != "..", name != ".app.lock" else {
            throw Failure.unsafeFile
        }
    }

    private static func privateFile(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_uid == getuid() &&
        info.st_mode & 0o777 == 0o600 && info.st_nlink == 1
    }
}
