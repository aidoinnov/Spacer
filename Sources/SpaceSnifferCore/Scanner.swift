import Foundation
import Darwin
import SpaceSnifferScanEngine

/// Lightweight UI progress; it never retains the growing node array.
public struct ScanProgress: Sendable {
    public let sequence: UInt64
    public let rootPath: String
    public let currentPath: String
    public let fileCount: Int
    public let folderCount: Int
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let visitedFolders: Int
    public let pendingFolders: Int
    public let issueCount: Int
    public var overview: ScanOverview? = nil
}

/// Per-scan counters, emitted once; these do not lock or log in the file loop.
/// Counts cover scanner enumeration, not Foundation's volume queries or libc's
/// implementation of readdir (a readdir call is not necessarily a syscall).
struct ScanIOStatistics: Codable, Sendable {
    var statCalls = 0
    var openDirectoryCalls = 0
    var readDirectoryCalls = 0
    var bulkCalls = 0
    var bulkReturnedRecords = 0
    var reusedMetadataEntries = 0
    var fallbackDirectories = 0
    var openRetryDecisions = 0
    var requestedRetryDelaySeconds = 0.0
    var bulkPreflightSkips = 0
    var bulkNameMismatches = 0
    var prefetchScheduled = 0
    var prefetchUsed = 0
    var prefetchDiscarded = 0
    var entryCountMetrics: EntryCountMetrics? = .init()

    mutating func mergeEnumeration(_ other: Self) {
        if let measured = other.entryCountMetrics, entryCountMetrics != nil {
            entryCountMetrics?.merge(measured)
        } else { entryCountMetrics = nil } // an unmeasured contribution stays unknown
        statCalls += other.statCalls; openDirectoryCalls += other.openDirectoryCalls
        readDirectoryCalls += other.readDirectoryCalls; bulkCalls += other.bulkCalls
        bulkReturnedRecords += other.bulkReturnedRecords; reusedMetadataEntries += other.reusedMetadataEntries
        fallbackDirectories += other.fallbackDirectories; openRetryDecisions += other.openRetryDecisions
        requestedRetryDelaySeconds += other.requestedRetryDelaySeconds
        bulkPreflightSkips += other.bulkPreflightSkips; bulkNameMismatches += other.bulkNameMismatches
    }
}

public enum DiskScanner {
    enum MetadataBackend: Sendable {
        case posix, bulk(NativeDirectoryMetadata), adaptive(NativeDirectoryMetadata)
        case streaming(NativeDirectoryMetadata), ordered(NativeDirectoryMetadata), automatic(NativeDirectoryMetadata)
    }
    static var orderedMetadataBackend: MetadataBackend {
        .ordered(.orderedScan)
    }
    // Device policy is evaluated per run, including nested mounts.
    static let defaultMetadataBackend: MetadataBackend = .automatic(.orderedScan)
    /// A single worker owns all mutable scan data. Symlinks/reparse entries are skipped.
    public static func scan(_ url: URL, control: ScanControl = ScanControl(),
                            volumeTraversal: ScanVolumeTraversal = .selectedVolume, scopeRoot: URL? = nil,
                            progress: (@Sendable (ScanSnapshot) -> Void)? = nil,
                            heartbeat: (@Sendable (ScanProgress) -> Void)? = nil) -> ScanSnapshot {
        scan(url, control: control, metadataBackend: defaultMetadataBackend, volumeTraversal: volumeTraversal,
             scopeRoot: scopeRoot, directoryConcurrency: MacScanResources.defaultConcurrency, progress: progress, heartbeat: heartbeat)
    }
    static func scan(_ url: URL, control: ScanControl = ScanControl(), metadataBackend: MetadataBackend,
                     volumeTraversal: ScanVolumeTraversal = .selectedVolume, scopeRoot: URL? = nil,
                     directoryConcurrency: Int = 1, siblingSampling: MacScanResources.SiblingSampling = MacScanResources.siblingSampling, overviewDelay: TimeInterval = 0.05,
                     progress: (@Sendable (ScanSnapshot) -> Void)? = nil,
                     heartbeat: (@Sendable (ScanProgress) -> Void)? = nil,
                     diagnostics: ((ScanIOStatistics) -> Void)? = nil) -> ScanSnapshot {
        precondition([1, 2, 4].contains(directoryConcurrency))
        var io = ScanIOStatistics()
        var overview = ScanOverviewAccumulator()
        let wantsOverview = heartbeat != nil
        var overviewActive = false
        defer { diagnostics?(io) }
        let rootURL = url.standardizedFileURL
        var snapshot = ScanSnapshot(rootPath: rootURL.path)
        var observedBytes = ObservedByteBatch()
        snapshot.volumeCoverage = ScanVolumeCoverage(traversal: volumeTraversal)
        var volumePolicy: ScanVolumePolicy?
        var deviceRule: ScanVolumePolicy.DeviceRule?
        let fm = FileManager.default
        let accountingURL = scopeRoot?.standardizedFileURL ?? rootURL
        if let attrs = try? fm.attributesOfFileSystem(forPath: accountingURL.path) {
            snapshot.volumeTotal = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            snapshot.volumeFree = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
        if accountingURL == rootURL, let values = try? rootURL.resourceValues(forKeys: [.volumeURLKey]) {
            snapshot.isVolumeRoot = values.volume?.standardizedFileURL.path == rootURL.path
        }
        func recordIssue(_ path: String, _ message: String) {
            snapshot.issueCount += 1
            if snapshot.issues.count < 500 { snapshot.issues.append("\(path): \(message)") }
        }
        func append(_ path: () -> String, name: String, parent: Int?, metadata: NativeFileMetadata? = nil, sharedBase: String? = nil) -> (id: Int, device: dev_t)? {
            let info: NativeFileMetadata
            if let metadata { info = metadata; io.reusedMetadataEntries += 1 }
            else {
                var value = stat()
                io.statCalls += 1
                guard lstat(path(), &value) == 0 else {
                    let code = errno
                    recordIssue(path(), String(cString: strerror(code))); return nil
                }
                info = NativeFileMetadata(value)
            }
            let directory = info.isDirectory
            let symbolic = info.isSymbolicLink
            if symbolic { return nil } // Native enumeration skips symlink/reparse entries (0x455be0).
            if deviceRule?.excludes(info.device) == true {
                snapshot.volumeCoverage?.exclude(path(), reason: "different_device"); return nil
            }
            let regular = info.isRegular
            let logical: Int64 = info.logicalBytes
            let allocated: Int64 = info.allocatedBytes
            let id = snapshot.nodes.count
            let storedPath: NodePathStorage
            if let sharedBase, !directory { storedPath = NodePathStorage(base: sharedBase, leaf: name) }
            else { storedPath = NodePathStorage(wrappedValue: path()) }
            var newNode = DiskNode(id: id, parent: parent, storedPath: storedPath,
                name: name.isEmpty ? path() : name,
                isDirectory: directory, isSymbolicLink: symbolic, logicalBytes: logical,
                allocatedBytes: allocated, modified: Date(timeIntervalSince1970: Double(info.modifiedSeconds)))
            newNode.setNativeFileIdentity(device: Int64(info.device), inode: UInt64(info.inode))
            newNode.ownAllocatedBytes = allocated
            newNode.created = Date(timeIntervalSince1970: Double(info.createdSeconds))
            newNode.accessed = Date(timeIntervalSince1970: Double(info.accessedSeconds))
            var attributes: UInt32 = directory ? 0x10 : 0
            if info.permissions & 0o222 == 0 { attributes |= 1 }
            if name.hasPrefix(".") || info.flags & UInt32(UF_HIDDEN) != 0 { attributes |= 2 }
            if info.flags & UInt32(UF_COMPRESSED) != 0 { attributes |= 0x800 }
            if regular && logical > allocated { attributes |= 0x200 }
            newNode.nativeAttributes = attributes
            newNode.nativeFlags = 0
            newNode.nativeType = directory ? (id == 0 && snapshot.isVolumeRoot ? 1 : 3) : 2
            snapshot.nodes.append(newNode)
            if let parent { snapshot.nodes[parent].children.append(id) }
            // Native deltaSize 0x405a00 updates ancestors as a file is discovered.
            // Do not copy and re-sum millions of nodes for every progress tick.
            if let parent, logical != 0 || allocated != 0 {
                observedBytes.add(parent: parent, logical: logical, allocated: allocated)
            }
            if directory { snapshot.folderCount += 1 } else {
                snapshot.fileCount += 1
            }
            return (id, info.device)
        }
        guard let rootEntry = append({ rootURL.path }, name: rootURL.lastPathComponent, parent: nil) else {
            snapshot.cancelled = control.isCancelled; snapshot.finished = Date(); return snapshot
        }
        let root = rootEntry.id
        let anchor = scopeRoot?.standardizedFileURL.path ?? rootURL.path
        var anchorDevice = rootEntry.device
        if anchor != rootURL.path {
            var value = stat()
            guard lstat(anchor, &value) == 0 else {
                let code = errno
                snapshot.nodes = []; snapshot.fileCount = 0; snapshot.folderCount = 0
                recordIssue(anchor, String(cString: strerror(code))); snapshot.finished = Date(); return snapshot
            }
            anchorDevice = value.st_dev
        }
        volumePolicy = ScanVolumePolicy.discover(traversal: volumeTraversal, anchor: anchor, device: anchorDevice)
        if volumePolicy?.inventoryComplete == false { recordIssue(anchor, "볼륨 경계 목록을 확인하지 못했습니다. 검사 범위가 불완전할 수 있습니다.") }
        if let reason = volumePolicy?.exclusion(path: rootURL.path, device: rootEntry.device, isScanRoot: true) {
            snapshot.volumeCoverage?.exclude(rootURL.path, reason: reason)
            snapshot.nodes = []; snapshot.fileCount = 0; snapshot.folderCount = 0; snapshot.finished = Date(); return snapshot
        }
        deviceRule = volumePolicy?.deviceRule
        let hasMountBoundaries = volumePolicy?.mountRoots.isEmpty == false
        let rootHint: UInt32?
        if case .adaptive(let reader) = metadataBackend { rootHint = reader.entryCount(rootURL.path, control: control, observeQuery: { io.entryCountMetrics?.record($0) }) }
        else { rootHint = nil }
        // Transient traversal hints only; DiskNode/NodeTable shape is unchanged.
        var stack: [(id: Int, hint: UInt32?, device: dev_t, rootBranch: Int)] = [(root, rootHint, rootEntry.device, root)]
        var currentRootBranch = root
        var metadataPolicy = ScanMetadataPolicy()
        var prefetched = DirectoryReadWindow<Int, DirectoryReadOutput>(futureCapacity: directoryConcurrency - 1)
        // Drain before the diagnostics defer and terminal return. A cancelled
        // scan never publishes completion while its private readers still run.
        defer {
            if control.isCancelled, !prefetched.isEmpty { DirectoryReadPool.shared.cancelQueued(control: control) }
            for ticket in prefetched.values { io.mergeEnumeration(ticket.wait().statistics) }
        }
        var lastUpdate = Date.distantPast
        var publication = ScanPublication()
        var visitedFolders = 0
        var progressSequence: UInt64 = 0
        var siblingAdmission = DirectorySiblingAdmission<Int>(recheckAfter: siblingSampling.recheckAfter)
        let readWindow = MacScanResources.readWindow(concurrency: directoryConcurrency)
        func report(_ path: String, force: Bool = false) {
            // Every externally observable snapshot/heartbeat has exact sums.
            // Also flush at directory boundaries even when publication is
            // throttled; the next directory may have a different parent.
            if let delta = observedBytes.drain() {
                snapshot.nodes.addObservedBytes(logical: delta.logical, allocated: delta.allocated, startingAt: delta.parent)
                if overviewActive { overview.markRootChanged(currentRootBranch) }
            }
            let now = Date()
            var firstUsefulOverview = false
            if wantsOverview, !overviewActive, !force, snapshot.fileCount > 0,
               now.timeIntervalSince(snapshot.started) >= overviewDelay {
                overviewActive = true
                firstUsefulOverview = true
            }
            guard force || firstUsefulOverview || now.timeIntervalSince(lastUpdate) > 0.6 else { return }
            if overviewActive { overview.update(from: snapshot) }
            progressSequence += 1
            heartbeat?(ScanProgress(sequence: progressSequence, rootPath: snapshot.rootPath, currentPath: path,
                fileCount: snapshot.fileCount, folderCount: snapshot.folderCount,
                logicalBytes: snapshot.nodes[root].logicalBytes, allocatedBytes: snapshot.nodes[root].allocatedBytes,
                visitedFolders: visitedFolders, pendingFolders: stack.count, issueCount: snapshot.issueCount,
                overview: overviewActive ? overview.value : nil))
            if progress != nil, publication.shouldPublish(nodeCount: snapshot.nodes.count) { progress?(snapshot) }
            lastUpdate = Date()
        }
        // The sole builder owns this bounded window. Completed results still
        // occupy a slot until consumed; workers never mutate IDs or the tree.
        func replenishReadAhead(skipNext: Bool) {
            if readWindow.hasVacancy(outstanding: prefetched.count, pending: stack.count), !control.isCancelled,
               let next = stack.last, let parent = snapshot.nodes[next.id].parent,
               stack.reversed().prefix(2).allSatisfy({ snapshot.nodes[$0.id].parent == parent }) {
                let enabled: Bool
                if let cached = siblingAdmission.decision(for: parent) { enabled = cached }
                else {
                    guard stack.count >= readWindow.minimumSiblingCount,
                          stack.reversed().prefix(readWindow.minimumSiblingCount).allSatisfy({ snapshot.nodes[$0.id].parent == parent }) else { return }
                    var found = false
                    for candidate in stack.reversed().prefix(siblingSampling.probeLimit) {
                        guard snapshot.nodes[candidate.id].parent == parent else { break }
                        let reader: NativeDirectoryMetadata?
                        switch metadataBackend {
                        case .ordered(let native): reader = native
                        case .automatic(let native): reader = metadataPolicy.allowsBulk(path: snapshot.nodes[candidate.id].path, device: candidate.device) ? native : nil
                        default: reader = nil
                        }
                        io.entryCountMetrics?.admissionCandidatesExamined += 1
                        let hint: UInt32?
                        if let cachedHint = candidate.hint {
                            io.entryCountMetrics?.admissionHintHits += 1; hint = cachedHint
                        } else {
                            hint = reader?.entryCount(snapshot.nodes[candidate.id].path, control: control,
                                observeQuery: { io.entryCountMetrics?.record($0) })
                        }
                        if readWindow.admits(entryCount: hint) { found = true; break }
                    }
                    siblingAdmission.record(found, for: parent); enabled = found
                }
                guard enabled else { return }
                // Initial admission leaves one directory inline. After consuming
                // a ticket, refill immediately so its worker can take the next
                // directory while the builder assembles the current listing.
                prefetched.replenish(from: stack.reversed().dropFirst(skipNext ? 1 : 0), maximumPlans: directoryConcurrency, key: { $0.id }) { upcoming in
                    guard snapshot.nodes[upcoming.id].parent == parent else { return nil }
                    let path = snapshot.nodes[upcoming.id].path
                    let reader: NativeDirectoryMetadata?
                    switch metadataBackend {
                    case .ordered(let native): reader = native
                    case .automatic(let native): reader = metadataPolicy.allowsBulk(path: path, device: upcoming.device) ? native : nil
                    default: reader = nil
                    }
                    guard let reader,
                          let ticket = DirectoryReadPool.shared.submit(reader: MacDirectoryBatchReader(native: reader, volumePolicy: volumePolicy), path: path, control: control) else { return nil }
                    io.prefetchScheduled += 1
                    return ticket
                }
            }
        }
        let directoryReader = POSIXDirectoryReader()
        while let task = stack.popLast() {
            let id = task.id
            currentRootBranch = task.rootBranch
            if control.isCancelled { break }
            let node = snapshot.nodes[id]
            let directoryPath = node.path
            guard node.isDirectory else { continue }
            // Await outside the directory permit: fixed workers can always
            // finish their reads even with every ScanAdmission slot occupied.
            let ticket = prefetched.take(for: id)
            if ticket != nil { replenishReadAhead(skipNext: false) }
            let readAhead = ticket?.wait(progress: {
                if control.isCancelled { DirectoryReadPool.shared.cancelQueued(control: control) }
                report(directoryPath)
            })
            if let readAhead { io.mergeEnumeration(readAhead.statistics) }
            if control.isCancelled { break }
            guard MacScanResources.directoryIO.acquire(control: control) else { break }
            defer { MacScanResources.directoryIO.release() }
            let directoryBackend: MetadataBackend
            if case .automatic(let reader) = metadataBackend {
                directoryBackend = metadataPolicy.allowsBulk(path: directoryPath, device: task.device) ? .ordered(reader) : .posix
            } else { directoryBackend = metadataBackend }
            report(directoryPath)
            do {
                func discover(_ name: String, metadata: NativeFileMetadata? = nil, hint: UInt32? = nil) {
                    var cachedPath: String?
                    func path() -> String {
                        if let cachedPath { return cachedPath }
                        let value = SnapshotPath.joinPOSIX(directoryPath, name)
                        cachedPath = value
                        return value
                    }
                    // Known mount boundaries need no target lstat, which can
                    // itself block on a slow/unavailable network filesystem.
                    if hasMountBoundaries, metadata?.isDirectory != false, let reason = volumePolicy?.boundaryExclusion(path: path()) {
                        snapshot.volumeCoverage?.exclude(path(), reason: reason); return
                    }
                    if let child = append(path, name: name, parent: id, metadata: metadata, sharedBase: directoryPath), snapshot.nodes[child.id].isDirectory {
                        stack.append((child.id, hint, child.device, id == root ? child.id : task.rootBranch))
                    }
                    // Even one huge directory should report progress and honour cancellation.
                    if snapshot.nodes.count % 256 == 0 { report(path()) }
                }
                if case .streaming(let reader) = directoryBackend {
                    var delivered: Set<String> = []
                    let complete = reader.stream(directoryPath, control: control, observeCall: { count in
                        io.bulkCalls += 1; io.bulkReturnedRecords += max(0, Int(count))
                    }) { entries in
                        for entry in entries {
                            if control.isCancelled { break }
                            guard delivered.insert(entry.name).inserted else { continue }
                            discover(entry.name, metadata: entry.values)
                        }
                    }
                    // A failed later batch must not add previously published
                    // entries twice. Preserve their valid observations and use
                    // the same POSIX listing/error path for the unread remainder.
                    if !complete, !control.isCancelled {
                        io.fallbackDirectories += 1
                        for name in try directoryReader.names(at: directoryPath, control: control, statistics: &io, progress: { report(directoryPath) }) {
                            if control.isCancelled { break }
                            if delivered.insert(name).inserted { discover(name) }
                        }
                    }
                    visitedFolders += 1
                    report(directoryPath)
                    continue
                }
                var batch: [NativeDirectoryMetadata.Entry]?
                var listedNames: [String]?
                var validatedOrder = false
                if let readAhead {
                    switch readAhead.value {
                    case .listing(let listing):
                        listedNames = listing.names; batch = listing.entries; validatedOrder = true; io.prefetchUsed += 1
                    case .failure(let domain, let code): throw NSError(domain: domain, code: code)
                    case .retryInline: io.prefetchDiscarded += 1
                    case .cancelled: break
                    }
                }
                if !validatedOrder { switch directoryBackend {
                case .posix: batch = nil
                case .automatic: preconditionFailure("automatic resolved above")
                case .streaming: preconditionFailure("streaming handled above")
                case .ordered(let reader):
                    let listing = try OrderedDirectoryReader(native: reader).read(directoryPath, control: control, statistics: &io,
                        progress: { report(directoryPath) })
                    listedNames = listing.names; batch = listing.entries; validatedOrder = true
                case .bulk(let reader): batch = reader.read(directoryPath, control: control, observeCall: { count in
                    io.bulkCalls += 1; io.bulkReturnedRecords += max(0, Int(count))
                })
                case .adaptive(let reader):
                    if let count = task.hint, count <= reader.maximumEntries {
                        batch = reader.read(directoryPath, control: control, includeDirectoryCounts: true, observeCall: { count in
                            io.bulkCalls += 1; io.bulkReturnedRecords += max(0, Int(count))
                        })
                    } else { batch = nil }
                } }
                if !validatedOrder { batch?.sort { $0.name < $1.name } }
                if let entries = batch {
                    // Namespace validation is complete; retain no second name
                    // list while the builder grows the full node table.
                    listedNames = nil
                    for (index, entry) in entries.enumerated() {
                        if index & 63 == 0, control.isCancelled { break }
                        discover(entry.name, metadata: entry.values, hint: entry.directoryEntryCount)
                    }
                } else {
                    if case .bulk = directoryBackend { io.fallbackDirectories += 1 }
                    if case .ordered = directoryBackend { io.fallbackDirectories += 1 }
                    let children = try listedNames ?? directoryReader.names(at: directoryPath, control: control, statistics: &io, progress: { report(directoryPath) })
                    for (index, name) in children.enumerated() {
                        if index & 63 == 0, control.isCancelled { break }
                        discover(name)
                    }
                }
            } catch {
                let message = error.localizedDescription
                snapshot.nodes[id].issue = message
                recordIssue(directoryPath, message)
            }
            visitedFolders += 1
            report(directoryPath)
            replenishReadAhead(skipNext: true)
        }
        if control.isCancelled, !prefetched.isEmpty { DirectoryReadPool.shared.cancelQueued(control: control) }
        for ticket in prefetched.values { io.mergeEnumeration(ticket.wait().statistics) }
        prefetched.removeAll()
        snapshot.cancelled = control.isCancelled
        snapshot.finished = Date()
        report(rootURL.path, force: true)
        return snapshot
    }
}
