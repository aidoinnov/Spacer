import Foundation

/// An injectable filesystem boundary. The default is the unchanged native scanner.
public typealias DirectoryScanOperation = @Sendable (URL, ScanControl,
    (@Sendable (ScanSnapshot) -> Void)?, (@Sendable (ScanProgress) -> Void)?) -> ScanSnapshot

/// One admitted scan's filesystem/fallback/merge calculation. It does not own root
/// subscriptions, admission policy, public revisions or UI state.
enum ScanWork {
    /// A bounded issue sample cannot identify which omitted errors belonged to
    /// the replaced branch. Re-enumerate the root rather than silently lowering
    /// the total to the number of retained issue strings.
    static func requiresRootRefresh(_ snapshot: ScanSnapshot) -> Bool {
        snapshot.issueCount > snapshot.issues.count ||
            (snapshot.volumeCoverage.map { $0.excludedCount > $0.exclusions.count } ?? false)
    }

    static func run(original: ScanSnapshot, scope: String, control: ScanControl,
                    scanner: DirectoryScanOperation,
                    progress: @escaping @Sendable (ScanSnapshot) -> Void,
                    heartbeat: @escaping @Sendable (ScanProgress) -> Void) -> ScanSnapshot {
        let key = original.rootPath
        let fullScan = scope == key || original.nodes.isEmpty || requiresRootRefresh(original)
        WorkerTelemetry.shared.record("scan.enumeration")
        var target = fullScan ? key : scope
        var result = scanner(URL(fileURLWithPath: target), control, fullScan ? progress : nil, heartbeat)
        while result.nodes.isEmpty, target != key, !control.isCancelled {
            target = URL(fileURLWithPath: target).deletingLastPathComponent().path
            result = scanner(URL(fileURLWithPath: target), control, nil, nil)
        }
        // An incomplete rescan is not proof that previously known children were
        // deleted (native 0x455be0 performs that removal at terminal enumeration).
        // Retain the prior whole-root tree, explicitly marked cancelled. An
        // initial scan without a cached tree retains its readable partial data.
        if control.isCancelled || result.cancelled {
            var retained = original.nodes.isEmpty ? result : original
            retained.cancelled = true; retained.finished = Date()
            return retained
        }
        if fullScan || target == key { return result }
        WorkerTelemetry.shared.record("scan.merge")
        if let merged = SnapshotTree.replacing(original, with: result, control: control) { return merged }
        var retained = original
        if control.isCancelled { retained.cancelled = true; retained.finished = Date() }
        return retained
    }
}
