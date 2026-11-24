import Foundation

/// The GPUI adapter uses the exact native selection and streaming encoders.
public enum ExplorerSemantics {
    public static func weights(_ snapshot: ScanSnapshot, text: String, mode: SizeMode, hidden: Bool) throws -> [Int64] {
        try ScanFilter(text).weights(in: snapshot, mode: mode, showHidden: hidden)
    }
    public static func write<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, text: String, mode: SizeMode, hidden: Bool,
                                                root: Int, report: Bool, to sink: inout S) throws {
        guard snapshot.nodes.indices.contains(root) else { throw SnapshotError.invalid }
        let filter = try ScanFilter(text)
        let now = Date()
        if report {
            let selection = ArtifactSelection.report(snapshot, filter: filter, mode: mode, showHidden: hidden, now: now)
            try Report.write(snapshot, selected: selection.selected, weights: selection.weights, root: root, to: &sink)
        } else {
            let selected = ArtifactSelection.snapshot(snapshot, filter: filter, showHidden: hidden, now: now)
            try SNSSnapshot.write(snapshot, selected: selected, root: root, to: &sink)
        }
    }
}

extension ExplorerSemantics {
    /// The same native XML codecs serve standalone templates and config bundles.
    public static func exportConfigurations(_ xml: Data, codePage: UInt32? = nil) throws -> [NativeConfiguration.ExportConfiguration] {
        try NativeConfiguration.decodeExportConfigurations(xml,codePage:codePage)
    }
    public static func configuredReport<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, xml: Data, index: Int,
            text: String, mode: SizeMode, hidden: Bool, root: Int, codePage: UInt32? = nil, maximumOutputBytes:Int64 = 1_073_741_824,to sink: inout S) throws {
        let configurations = try exportConfigurations(xml, codePage: codePage)
        guard configurations.indices.contains(index) else { throw SnapshotError.invalid }
        _ = try ConfiguredReport.write(snapshot, configuration: configurations[index], filter: ScanFilter(text),
            showHidden: hidden, root: root, sortMode: mode, formatting: ExplorerExportFormatting.localized(), maximumOutputBytes:maximumOutputBytes,to: &sink)
    }
}
