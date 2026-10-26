import Foundation
import Darwin

/// A saved record grants authority over one child, never every copy of a binary.
final class AgentChildOwnership {
    struct Identity: Codable, Equatable {
        let pid: Int32
        let uid: UInt32
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
        let executable: String
    }
    struct Record: Codable, Equatable {
        let rootDevice: Int32
        let rootInode: UInt64
        let child: Identity
    }
    private let location: AppStateLocation
    private var current: Record?
    private var currentProcess: Process?
    init(location: AppStateLocation) { self.location = location }

    func recover(binaryPath: String) throws {
        guard let data = try location.read("child.json") else { return }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.rootDevice == location.device, record.rootInode == location.inode,
              record.child.uid == getuid(), record.child.pid > 1,
              record.child.pid != getpid() else {
            throw AppStateLocation.Failure.unsafeFile
        }
        if let actual = try Self.identity(record.child.pid) {
            // A stale or reused PID never grants authority over the replacement.
            guard actual == record.child,
                  actual.executable == URL(fileURLWithPath: binaryPath).resolvingSymlinksInPath().path else {
                throw AppStateLocation.Failure.unsafeFile
            }
            guard kill(actual.pid, SIGTERM) == 0 || errno == ESRCH else { throw AppStateLocation.Failure.io }
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while try Self.identity(actual.pid) == actual {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw AppStateLocation.Failure.busy }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        // Only the exact record read above may be retired.
        guard try location.read("child.json") == data else { throw AppStateLocation.Failure.unsafeFile }
        try location.remove("child.json")
    }

    func register(_ process: Process, binaryPath: String) throws {
        guard let identity = try Self.identity(process.processIdentifier),
              identity.uid == getuid(),
              identity.executable == URL(fileURLWithPath: binaryPath).resolvingSymlinksInPath().path else {
            throw AppStateLocation.Failure.unsafeFile
        }
        let record = Record(rootDevice: location.device, rootInode: location.inode, child: identity)
        guard try location.read("child.json") == nil else { throw AppStateLocation.Failure.busy }
        try location.write(JSONEncoder().encode(record), name: "child.json")
        current = record
        currentProcess = process
    }

    func retire(_ process: Process) {
        guard let current, currentProcess === process,
              !process.isRunning else { return }
        do {
            guard let data = try location.read("child.json"),
                  try JSONDecoder().decode(Record.self, from: data) == current else { return }
            try location.remove("child.json")
            self.current = nil
            currentProcess = nil
        } catch { /* Keep unknown state for the next locked startup to reject. */ }
    }

    static func identity(_ pid: Int32) throws -> Identity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        if count == 0 && (errno == ESRCH || kill(pid, 0) < 0 && errno == ESRCH) { return nil }
        guard count == size else { throw AppStateLocation.Failure.io }
        // Darwin's SZOMB means the child has exited and cannot run or be signalled.
        if info.pbi_status == 5 { return nil }
        // Darwin defines PROC_PIDPATHINFO_MAXSIZE as this expression; Swift cannot import that macro.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else { throw AppStateLocation.Failure.io }
        return Identity(pid: pid, uid: info.pbi_uid, startedSeconds: info.pbi_start_tvsec,
                        startedMicroseconds: info.pbi_start_tvusec, executable: String(cString: path))
    }
}
