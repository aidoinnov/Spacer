import Foundation
import SpaceSnifferScanEngine

typealias OrderedDirectoryListing = DirectoryListing<NativeFileMetadata>

/// One owner for names-first ordering, preflight, native validation and fallback.
/// Inline preflight and bounded worker census preserve the same namespace contract.
struct OrderedDirectoryReader: Sendable {
    let native: NativeDirectoryMetadata

    private struct RawName: Hashable {
        let value: String
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.value.utf8.elementsEqual(rhs.value.utf8) }
        func hash(into hasher: inout Hasher) {
            if value.utf8.withContiguousStorageIfAvailable({ hasher.combine(bytes: UnsafeRawBufferPointer($0)) }) == nil {
                Array(value.utf8).withUnsafeBytes { hasher.combine(bytes: $0) }
            }
        }
    }

    /// Validate the full raw-byte namespace before touching entries. The index
    /// dies on return, before the caller borrows the sole metadata array.
    private static func destinations(_ entries: [NativeDirectoryMetadata.Entry], names: [String]) -> [Int]? {
        guard entries.count == names.count else { return nil }
        var indices: [RawName: Int] = [:]
        indices.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            guard indices.updateValue(index, forKey: RawName(value: entry.name)) == nil else { return nil }
        }
        var destinations = [Int](repeating: 0, count: entries.count)
        for (destination, name) in names.enumerated() {
            guard let source = indices.removeValue(forKey: RawName(value: name)) else { return nil }
            destinations[source] = destination
        }
        return destinations
    }

    /// Move each complete entry to its validated destination. An Int per entry
    /// replaces a second full metadata array. No partial permutation is visible
    /// on validation failure; Array's CoW protects any external reader.
    static func orderEntries(_ entries: inout [NativeDirectoryMetadata.Entry], names: [String]) -> Bool {
        guard var destinations = destinations(entries, names: names) else { return false }
        entries.withUnsafeMutableBufferPointer { buffer in
            for position in buffer.indices {
                while destinations[position] != position {
                    let destination = destinations[position]
                    buffer.swapAt(position, destination)
                    destinations.swapAt(position, destination)
                }
            }
        }
        return true
    }

    static func prefetch(_ path: String, control: ScanControl, native: NativeDirectoryMetadata? = nil) -> DirectoryReadOutput {
        var statistics = ScanIOStatistics()
        let reader = Self(native: (native ?? .orderedScan).boundedForReadAhead())
        do {
            let listing = try reader.readVerifiedBatch(path, control: control, statistics: &statistics)
            return DirectoryReadOutput(value: control.isCancelled ? .cancelled : .listing(listing), statistics: statistics)
        } catch DirectoryNameBudgetError.exceeded {
            return DirectoryReadOutput(value: .retryInline, statistics: statistics)
        } catch {
            let error = error as NSError
            return DirectoryReadOutput(value: .failure(domain: error.domain, code: error.code), statistics: statistics)
        }
    }

    /// The worker owns/sorts one bounded bulk collection. A separate streaming
    /// readdir census still verifies completeness: two OS enumerations, without
    /// a second retained/sorted name collection. Inline wide-folder preflight
    /// remains names-first to avoid a large failed speculative allocation.
    private func readVerifiedBatch(_ path: String, control: ScanControl,
                                   statistics: inout ScanIOStatistics) throws -> OrderedDirectoryListing {
        var calls = 0, records = 0
        var batch = native.readCensusCandidate(path, control: control, polling: .batch64, observeCall: { count in
            calls += 1; records += max(0, Int(count))
        })
        statistics.bulkCalls += calls; statistics.bulkReturnedRecords += records
        guard !control.isCancelled else { return .init(names: [], entries: nil) }
        guard batch != nil else {
            let names = try POSIXDirectoryReader().names(at: path, control: control, statistics: &statistics,
                budget: (2048, 128 * 1024), progress: {})
            return .init(names: names, entries: nil)
        }
        batch!.sort { $0.name < $1.name }
        var remaining = Set<RawName>()
        for entry in batch! {
            guard remaining.insert(RawName(value: entry.name)).inserted else {
                statistics.bulkNameMismatches += 1
                return try read(path, control: control, statistics: &statistics,
                                allowSmallDirectory: true, nameBudget: (2048, 128 * 1024), progress: {})
            }
        }
        let matched = try POSIXDirectoryReader().visitNames(at: path, control: control, statistics: &statistics,
            budget: (2048, 128 * 1024), progress: {}) { remaining.remove(RawName(value: $0)) != nil }
        guard !control.isCancelled else { return .init(names: [], entries: nil) }
        guard matched, remaining.isEmpty else {
            statistics.bulkNameMismatches += 1
            return try read(path, control: control, statistics: &statistics,
                            allowSmallDirectory: true, nameBudget: (2048, 128 * 1024), progress: {})
        }
        return .init(names: batch!.map(\.name), entries: batch)
    }

    func read(_ path: String, control: ScanControl, statistics: inout ScanIOStatistics,
              includeDirectoryCounts: Bool = false, allowSmallDirectory: Bool = false,
              nameBudget: (entries: Int, bytes: Int)? = nil,
              polling: DirectoryReadPolling = .batch64,
              progress: () -> Void) throws -> OrderedDirectoryListing {
        let names = try POSIXDirectoryReader().names(at: path, control: control, statistics: &statistics, budget: nameBudget, polling: polling, progress: progress)
        var batch: [NativeDirectoryMetadata.Entry]?
        if names.isEmpty { batch = [] }
        else if native.fits(names, control: control, allowSmallDirectory: allowSmallDirectory) {
            var calls = 0, records = 0
            batch = native.read(path, control: control, includeDirectoryCounts: includeDirectoryCounts, capacityHint: names.count, polling: polling, observeCall: { count in
                calls += 1; records += max(0, Int(count))
            })
            statistics.bulkCalls += calls; statistics.bulkReturnedRecords += records
        } else { statistics.bulkPreflightSkips += 1 }
        if (batch?.count ?? 0) >= 4096 {
            // Do not bind a second Array value here: that would force a CoW
            // copy when the validated permutation takes its mutable borrow.
            if !Self.orderEntries(&batch!, names: names) {
                statistics.bulkNameMismatches += 1; batch = nil
            }
        } else {
            batch?.sort { $0.name < $1.name }
            if let entries = batch, names.count != entries.count || !zip(names, entries).allSatisfy({ $0.utf8.elementsEqual($1.name.utf8) }) {
                statistics.bulkNameMismatches += 1; batch = nil
            }
        }
        return OrderedDirectoryListing(names: names, entries: batch)
    }
}
