import Foundation
import Darwin

/// Short checks run inside admitted blocking I/O, never on the service actor.
/// They narrow queued-request replacement/symlink races; they are not an atomic
/// filesystem snapshot or a replacement for the scanner's own error handling.
enum FocusScanTarget {
    static func matches(_ request: FocusScanRequest, original: ScanSnapshot) -> Bool {
        guard SnapshotTree.contains(original.rootPath, request.scope),
              let root = original.nodes.first, root.isDirectory,
              matchesDirectory(original.rootPath, identity: root.fileIdentity),
              matchesDirectory(request.scope, identity: request.targetIdentity),
              let rootPath = resolved(original.rootPath), let scope = resolved(request.scope),
              SnapshotTree.contains(rootPath, scope) else { return false }
        return true
    }
    private static func matchesDirectory(_ path: String, identity: String?) -> Bool {
        var value = stat()
        guard lstat(path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { return false }
        return identity.map { $0 == "\(value.st_dev):\(value.st_ino)" } ?? true
    }
    private static func resolved(_ path: String) -> String? {
        guard let value = realpath(path, nil) else { return nil }
        defer { free(value) }; return String(cString: value)
    }
    static func invalidated(_ original: ScanSnapshot) -> ScanSnapshot {
        var retained = original; retained.cancelled = true; retained.finished = Date(); return retained
    }
}
