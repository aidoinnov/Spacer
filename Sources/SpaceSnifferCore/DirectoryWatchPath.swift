/// Translate native event paths to the cached root spelling without consulting
/// the event item. A removed item cannot reliably resolve its former aliases.
struct DirectoryWatchPath: Sendable {
    let root: String
    let nativeRoot: String

    func map(_ path: String) -> String {
        guard root != nativeRoot else { return path }
        if path == nativeRoot { return root }
        let prefix = nativeRoot.hasSuffix("/") ? nativeRoot : nativeRoot + "/"
        guard path.hasPrefix(prefix) else { return path }
        return SnapshotPath.joinPOSIX(root, String(path.dropFirst(prefix.count)))
    }
}
