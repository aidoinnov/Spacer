import Foundation

/// Path spelling shared by scanning, navigation and snapshot formats.
/// Joining preserves spelling and never normalizes path components.
public enum SnapshotPath {
    public static func isWindows(_ path: String) -> Bool {
        if path.hasPrefix("\\\\") { return true }
        guard !path.isEmpty else { return false }
        let second = path.index(after: path.startIndex)
        return second < path.endIndex && path[second] == ":"
    }
    public static func isAbsolute(_ path: String) -> Bool { path.hasPrefix("/") || isWindows(path) }
    public static func join(_ root: String, _ name: String) -> String {
        let separator = isWindows(root) ? "\\" : "/"
        return join(root, name, separator: separator)
    }
    /// The native scanner already knows its separator; avoid Windows-path
    /// classification for every file and reserve the joined spelling once.
    static func joinPOSIX(_ root: String, _ name: String) -> String {
        join(root, name, separator: "/")
    }
    private static func join(_ root: String, _ name: String, separator: String) -> String {
        let needsSeparator = !root.hasSuffix(separator)
        var joined = String()
        joined.reserveCapacity(root.utf8.count + name.utf8.count + (needsSeparator ? separator.utf8.count : 0))
        joined.append(root)
        if needsSeparator { joined.append(separator) }
        joined.append(name)
        return joined
    }
    public static func displayName(_ path: String) -> String {
        let parts = path.split(separator: isWindows(path) ? "\\" : "/")
        return parts.last.map(String.init) ?? path
    }
}

