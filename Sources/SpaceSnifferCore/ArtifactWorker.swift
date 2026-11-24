import Foundation

/// Async facade only. Formatting, output transactions and OS actions have their
/// own owners; blocking operations execute on the serial I/O queue, not this actor.
public actor ArtifactWorker {
    public static let shared = ArtifactWorker()
    private let executor: ArtifactIOExecutor
    public init() { executor = ArtifactIOExecutor() }
    init(executor: ArtifactIOExecutor) { self.executor = executor }
    public func inspectConfiguration(_ url: URL, legacyCodePage: UInt32? = nil, xmlTextCodePage: UInt32? = nil, control: ScanControl? = nil) async throws -> ConfigurationFile.Inspection {
        let control = control ?? ScanControl()
        return try await withTaskCancellationHandler {
            try await executor.run { try ConfigurationFile.inspect(url, legacyCodePage: legacyCodePage, xmlTextCodePage: xmlTextCodePage, control: control) }
        } onCancel: { control.cancel() }
    }
    @discardableResult
    public func exportConfigured(_ snapshot: ScanSnapshot, options: ConfiguredExportOptions, to url: URL,
                                 replaceExisting: Bool = true) async throws -> ConfiguredReport.Statistics {
        let control = options.control ?? ScanControl()
        let job = ConfiguredExportOptions(configuration: options.configuration, filter: options.filter, mode: options.mode,
            showHidden: options.showHidden, root: options.root, formatting: options.formatting, now: options.now,
            maximumOutputBytes: options.maximumOutputBytes, control: control)
        return try await withTaskCancellationHandler {
            try await executor.run {
                WorkerTelemetry.shared.record("report.configured-export")
                return try ArtifactTransfer.exportConfigured(snapshot, options: job, to: url, replaceExisting: replaceExisting)
            }
        } onCancel: { control.cancel() }
    }
    public func volumes() async throws -> [DiskVolume] {
        try await executor.run { WorkerTelemetry.shared.record("volumes.enumerate"); return DesktopFileActions.volumes() }
    }
    public func load(_ url: URL, legacyCodePage: UInt32? = nil, rootIndex: Int? = nil, control: ScanControl? = nil) async throws -> ScanSnapshot {
        let control = control ?? ScanControl()
        return try await withTaskCancellationHandler {
            try await executor.run { WorkerTelemetry.shared.record("snapshot.load"); return try ArtifactTransfer.load(url, legacyCodePage: legacyCodePage, rootIndex: rootIndex, control: control) }
        } onCancel: { control.cancel() }
    }
    public func inspectRoots(_ url: URL, legacyCodePage: UInt32? = nil, control: ScanControl? = nil) async throws -> [SNSSnapshot.RootInfo] {
        let control = control ?? ScanControl()
        return try await withTaskCancellationHandler {
            try await executor.run { try ArtifactTransfer.inspectRoots(url, legacyCodePage: legacyCodePage, control: control) }
        } onCancel: { control.cancel() }
    }
    public func save(_ snapshot: ScanSnapshot, ids: Set<Int>? = nil, root: Int = 0, to url: URL, replaceExisting: Bool = true) async throws {
        try await executor.run {
            WorkerTelemetry.shared.record("snapshot.save")
            try ArtifactTransfer.save(snapshot, ids: ids, root: root, to: url, replaceExisting: replaceExisting)
        }
    }
    public func save(_ snapshot: ScanSnapshot, filter: ScanFilter, showHidden: Bool, root: Int = 0, to url: URL, replaceExisting: Bool = true) async throws {
        let now = Date()
        try await executor.run {
            WorkerTelemetry.shared.record("snapshot.save")
            try ArtifactTransfer.save(snapshot, filter: filter, showHidden: showHidden, root: root, to: url, replaceExisting: replaceExisting, now: now)
        }
    }
    public func trash(_ url: URL) async throws {
        try await executor.run { WorkerTelemetry.shared.record("filesystem.trash"); try DesktopFileActions.trash(url) }
    }
    public func export(_ snapshot: ScanSnapshot, filter: ScanFilter, mode: SizeMode, showHidden: Bool, root: Int, to url: URL, replaceExisting: Bool = true) async throws {
        let now = Date()
        try await executor.run {
            WorkerTelemetry.shared.record("report.export")
            try ArtifactTransfer.export(snapshot, filter: filter, mode: mode, showHidden: showHidden, root: root, to: url, replaceExisting: replaceExisting, now: now)
        }
    }
}
