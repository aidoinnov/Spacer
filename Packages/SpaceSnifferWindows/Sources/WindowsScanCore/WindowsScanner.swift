import SpaceSnifferScanEngine
import WindowsDirectoryIO
/// Composition root: chooses the Windows I/O/path strategies and resource policy.
/// The tree builder receives readers by their shared DirectoryBatchReader port.
public enum WindowsScanner {
    public static func scan(root: String, control: ScanControl, workers: Int = 4, includeMountedVolumes:Bool = false,
                            progress: @Sendable (WindowsProgress) -> Void = { _ in }) -> WindowsSnapshot {
        let policy = WindowsScanPolicy(workers: workers)
        var snapshot = WindowsTreeBuilder.scan(root: WindowsPath.rootSpelling(root), control: control, policy: policy,
            boundedReader: WindowsDirectoryReader(maximumEntries: policy.prefetchEntryLimit,includeMountedVolumes:includeMountedVolumes),
            inlineReader: WindowsDirectoryReader(maximumEntries: .max,includeMountedVolumes:includeMountedVolumes), includeMountedVolumes:includeMountedVolumes,rootVolume:includeMountedVolumes ? WindowsVolumeIdentity.read(root,exactMount:false) : nil,progress: progress)
        var metadata=sniffer_root_metadata()
        (Array(WindowsPath.nativeSpelling(root).utf16)+[0]).withUnsafeBufferPointer { _ = sniffer_query_root($0.baseAddress,&metadata) }
        snapshot.volumeTotal=metadata.total_bytes;snapshot.volumeFree=metadata.free_bytes;snapshot.isVolumeRoot=metadata.is_volume_root != 0
        snapshot.nodes[0].createdTicks=metadata.created_ticks;snapshot.nodes[0].accessedTicks=metadata.accessed_ticks
        snapshot.nodes[0].modifiedTicks=metadata.modified_ticks;snapshot.nodes[0].attributes=metadata.attributes
        return snapshot
    }
}
