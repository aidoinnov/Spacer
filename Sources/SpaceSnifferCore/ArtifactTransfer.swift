import Foundation

/// Synchronous artifact operation. UI/MCP use ArtifactWorker's I/O executor;
/// headless CLI may call this directly without starting an AppKit event loop.
public enum ArtifactTransfer {
    @discardableResult
    public static func exportConfigured(_ snapshot: ScanSnapshot, options: ConfiguredExportOptions, to url: URL,
                                        replaceExisting: Bool = true) throws -> ConfiguredReport.Statistics {
        try exportConfigured(snapshot, options: options, to: url, replaceExisting: replaceExisting, io: NativeArtifactFileIO())
    }
    static func exportConfigured(_ snapshot: ScanSnapshot, options: ConfiguredExportOptions, to url: URL,
                                 replaceExisting: Bool, io: any ArtifactFileIO) throws -> ConfiguredReport.Statistics {
        if Task.isCancelled || options.control?.isCancelled == true { throw CancellationError() }
        let transaction = try ArtifactFileTransaction(to: url, replaceExisting: replaceExisting, io: ConfiguredExportFileIO(base: io, control: options.control))
        var sink = ArtifactFileSink(transaction)
        let result = try ConfiguredReport.write(snapshot, configuration: options.configuration, filter: options.filter,
            showHidden: options.showHidden, root: options.root, sortMode: options.mode, formatting: options.formatting,
            now: options.now, maximumOutputBytes: options.maximumOutputBytes, control: options.control, to: &sink)
        if Task.isCancelled || options.control?.isCancelled == true { throw CancellationError() }
        try sink.finish()
        return result
    }
    public static func load(_ url: URL, legacyCodePage: UInt32? = nil, rootIndex: Int? = nil, control: ScanControl? = nil) throws -> ScanSnapshot {
        if Task.isCancelled || control?.isCancelled == true { throw CancellationError() }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if DUSnapshot.accepts(filename: url.lastPathComponent) {
            return try DUSnapshot.decode(data, legacyCodePage: legacyCodePage, rootIndex: rootIndex, control: control)
        }
        return try SNSSnapshot.decode(data, legacyCodePage: legacyCodePage, rootIndex: rootIndex, control: control)
    }
    public static func inspectRoots(_ url: URL, legacyCodePage: UInt32? = nil, control: ScanControl? = nil) throws -> [SNSSnapshot.RootInfo] {
        if Task.isCancelled || control?.isCancelled == true { throw CancellationError() }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if DUSnapshot.accepts(filename: url.lastPathComponent) {
            return try DUSnapshot.decodeAll(data, legacyCodePage: legacyCodePage, control: control).enumerated().map { index, snapshot in
                SNSSnapshot.RootInfo(index: index, path: snapshot.rootPath, files: snapshot.fileCount, folders: snapshot.folderCount,
                    logicalBytes: snapshot.nodes[0].logicalBytes, allocatedBytes: snapshot.nodes[0].allocatedBytes)
            }
        }
        return try SNSSnapshot.inspectRoots(data, legacyCodePage: legacyCodePage, control: control)
    }
    public static func save(_ snapshot: ScanSnapshot, ids: Set<Int>? = nil, root: Int = 0, to url: URL, replaceExisting: Bool = true) throws {
        try save(snapshot, ids: ids, root: root, to: url, replaceExisting: replaceExisting, io: NativeArtifactFileIO())
    }
    static func save(_ snapshot: ScanSnapshot, ids: Set<Int>?, root: Int, to url: URL, replaceExisting: Bool, io: any ArtifactFileIO) throws {
        let transaction = try ArtifactFileTransaction(to: url, replaceExisting: replaceExisting, io: io)
        var sink = ArtifactFileSink(transaction)
        try SNSSnapshot.write(snapshot, ids: ids, root: root, to: &sink)
        try sink.finish()
    }
    public static func save(_ snapshot: ScanSnapshot, filter: ScanFilter, showHidden: Bool, root: Int = 0, to url: URL, replaceExisting: Bool = true, now: Date = Date()) throws {
        let selected = ArtifactSelection.snapshot(snapshot, filter: filter, showHidden: showHidden, now: now)
        let transaction = try ArtifactFileTransaction(to: url, replaceExisting: replaceExisting)
        var sink = ArtifactFileSink(transaction)
        try SNSSnapshot.write(snapshot, selected: selected, root: root, to: &sink)
        try sink.finish()
    }
    public static func export(_ snapshot: ScanSnapshot, filter: ScanFilter, mode: SizeMode, showHidden: Bool, root: Int = 0, to url: URL, replaceExisting: Bool = true, now: Date = Date()) throws {
        try export(snapshot, filter: filter, mode: mode, showHidden: showHidden, root: root, to: url,
            replaceExisting: replaceExisting, now: now, io: NativeArtifactFileIO())
    }
    static func export(_ snapshot: ScanSnapshot, filter: ScanFilter, mode: SizeMode, showHidden: Bool, root: Int, to url: URL, replaceExisting: Bool, now: Date, io: any ArtifactFileIO) throws {
        let selection = ArtifactProjection(snapshot, filter: filter, mode: mode, showHidden: showHidden, root: root, now: now)
        try export(selection, to: url, replaceExisting: replaceExisting, io: io)
    }
    public static func save(_ selection: ArtifactProjection, to url: URL, replaceExisting: Bool = true) throws {
        let transaction = try ArtifactFileTransaction(to: url, replaceExisting: replaceExisting)
        var sink = ArtifactFileSink(transaction)
        try SNSSnapshot.write(selection.snapshot, selected: selection.selected, root: selection.root, to: &sink)
        try sink.finish()
    }
    public static func export(_ selection: ArtifactProjection, to url: URL, replaceExisting: Bool = true) throws {
        try export(selection, to: url, replaceExisting: replaceExisting, io: NativeArtifactFileIO())
    }
    private static func export(_ selection: ArtifactProjection, to url: URL, replaceExisting: Bool, io: any ArtifactFileIO) throws {
        let transaction = try ArtifactFileTransaction(to: url, replaceExisting: replaceExisting, io: io)
        var sink = ArtifactFileSink(transaction)
        try Report.write(selection.snapshot, selected: selection.selected, weights: selection.weights, root: selection.root, to: &sink)
        try sink.finish()
    }
}
