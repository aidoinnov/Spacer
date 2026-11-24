import Foundation

/// Frozen app/CLI/MCP job inputs. The selected native configuration is explicit.
public struct ConfiguredExportOptions: Sendable {
    public let configuration: NativeConfiguration.ExportConfiguration
    public let filter: ScanFilter
    public let mode: SizeMode
    public let showHidden: Bool
    public let root: Int
    public let formatting: ConfiguredReport.Formatting
    public let now: Date
    public let maximumOutputBytes: Int64
    public let control: ScanControl?
    public init(configuration: NativeConfiguration.ExportConfiguration, filter: ScanFilter, mode: SizeMode = .allocated,
                showHidden: Bool = true, root: Int = 0, formatting: ConfiguredReport.Formatting = .init(), now: Date = Date(),
                maximumOutputBytes: Int64 = 1_073_741_824, control: ScanControl? = nil) {
        self.configuration = configuration; self.filter = filter; self.mode = mode; self.showHidden = showHidden; self.root = root
        self.formatting = formatting; self.now = now; self.maximumOutputBytes = maximumOutputBytes; self.control = control
    }
}

/// A cancelled flush cannot publish its staging file. The atomic rename remains
/// the commit point: cancellation arriving after that point cannot undo success.
struct ConfiguredExportFileIO: ArtifactFileIO {
    let base: any ArtifactFileIO
    let control: ScanControl?
    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) throws -> Int {
        try check(); return try base.write(descriptor, bytes: bytes)
    }
    func close(_ descriptor: Int32) throws { try base.close(descriptor) }
    func publish(_ temporary: String, to destination: String, replaceExisting: Bool) throws {
        try check(); try base.publish(temporary, to: destination, replaceExisting: replaceExisting)
    }
    private func check() throws { if Task.isCancelled || control?.isCancelled == true { throw CancellationError() } }
}
