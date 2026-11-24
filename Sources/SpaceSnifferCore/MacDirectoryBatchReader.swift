import Darwin
import SpaceSnifferScanEngine

/// OS I/O only: workers complete bounded metadata, never tree/ID/ancestor state.
struct MacDirectoryBatchReader: DirectoryBatchReader {
    typealias StatCall = @Sendable (String, inout stat) -> Int32
    let native: NativeDirectoryMetadata
    var volumePolicy: ScanVolumePolicy? = nil
    var statCall: StatCall = { lstat($0, &$1) }
    func readDirectory(at path: String, control: ScanControl) -> DirectoryReadOutput {
        let output = OrderedDirectoryReader.prefetch(path, control: control, native: native)
        guard case .listing(let listing) = output.value else { return output }
        let bounded = native.boundedForReadAhead()
        guard bounded.fits(listing.names, control: control, allowSmallDirectory: true) else {
            return DirectoryReadOutput(value: control.isCancelled ? .cancelled : .retryInline, statistics: output.statistics)
        }
        return completeMetadata(listing, at: path, control: control, statistics: output.statistics)
    }

    /// Bounded completion only; the reader already verified namespace/budgets.
    /// Kept separate so cancellation can be tested at the real stat boundary.
    func completeMetadata(_ listing: OrderedDirectoryListing, at path: String, control: ScanControl,
                          statistics initialStatistics: ScanIOStatistics = .init()) -> DirectoryReadOutput {
        var statistics = initialStatistics
        var entries = listing.entries ?? listing.names.map { NativeDirectoryMetadata.Entry(name: $0, values: nil, directoryEntryCount: nil) }
        for index in entries.indices {
            if index & 63 == 0, control.isCancelled { return DirectoryReadOutput(value: .cancelled, statistics: statistics) }
            guard entries[index].values == nil else { continue }
            let item = entries[index]
            let child = SnapshotPath.joinPOSIX(path, item.name)
            // Do not trigger an excluded mount/automount just to prefetch stat.
            if volumePolicy?.boundaryExclusion(path: child) != nil { continue }
            guard !control.isCancelled else { return DirectoryReadOutput(value: .cancelled, statistics: statistics) }
            var value = stat(); statistics.statCalls += 1
            if statCall(child, &value) == 0 {
                entries[index] = .init(name: item.name, values: NativeFileMetadata(value), directoryEntryCount: item.directoryEntryCount)
            }
            // Failed stat stays nil: builder keeps its existing final error/
            // race observation instead of accepting a fabricated metadata row.
        }
        return DirectoryReadOutput(value: control.isCancelled ? .cancelled : .listing(.init(names: listing.names, entries: entries)), statistics: statistics)
    }
}
