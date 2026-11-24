import Foundation

public struct VolumeAccounting: Sendable {
    public let total: Int64
    public let free: Int64
}
/// Short metadata I/O is isolated from both long artifact transfers and the
/// cooperative executor. One native operation +64 queued, independent of scan8.
public enum PathIO {
    static let executor = ArtifactIOExecutor(label: "space-sniffer.path-io", stage: "path.io")
    private static func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let control = ScanControl()
        return try await withTaskCancellationHandler {
            let result = try await executor.run { guard !control.isCancelled else { throw CancellationError() }; return try operation() }
            try Task.checkCancellation(); return result
        } onCancel: { control.cancel() }
    }
    public static func canonical(_ url: URL) async throws -> URL {
        try await run { url.standardizedFileURL.resolvingSymlinksInPath() }
    }
    public static func isDirectory(_ url: URL) async throws -> Bool {
        try await run { var directory: ObjCBool = false; return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue }
    }
    public static func exists(_ url: URL) async throws -> Bool {
        try await run { FileManager.default.fileExists(atPath: url.path) }
    }
    public static func volume(_ url: URL) async throws -> VolumeAccounting {
        try await run {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
            return VolumeAccounting(total: (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0, free: (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
        }
    }
}
