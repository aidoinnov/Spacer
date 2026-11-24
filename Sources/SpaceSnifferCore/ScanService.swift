import Foundation

public struct ScanUpdate: Sendable {
    public let snapshot: ScanSnapshot
    public let isScanning: Bool
    public let revision: UInt64
    public let watchActive: Bool
    public let scope: String
    public let progress: ScanProgress?
    public let schedulingError: String?
}
public struct ScanSubscription: Sendable {
    public let id: UUID
    public let rootPath: String
    public let updates: AsyncStream<ScanUpdate>
}
public struct EngineStatistics: Sendable {
    public let roots: Int
    public let subscribers: Int
    public let scanStarts: Int
    public let admission: ScanAdmissionStatistics
}

/// Root-data cache and worker lifecycle reconstructed from TDataCache/TRootData.
/// Actor isolation replaces the Windows multi-reader/exclusive-writer locks.
public actor ScanService {
    typealias MonitorDelivery = @Sendable ([PathChange]) async -> Void
    typealias MonitorFactory = @Sendable (String, @escaping MonitorDelivery) -> AnyObject?
    public static let shared = ScanService()
    public static let includingMountedVolumes = ScanService(volumeTraversal: .allVolumes)
    private final class Entry {
        let url: URL
        var snapshot: ScanSnapshot
        var tags: [String: Int] = [:]
        var baseline = NodeTable()
        var subscribers: [UUID: AsyncStream<ScanUpdate>.Continuation] = [:]
        var watchers: Set<UUID> = []
        var monitor: AnyObject?
        var control: ScanControl?
        var job: UUID?
        var generation = UUID()
        var revision: UInt64 = 0
        var schedulingError: String?
        var progress: ScanProgress?
        var scanning = false
        var scope: String
        var restartScope: String?
        let incarnation: UUID
        var focus: FocusScanRequests
        var focusJob: FocusScanRequest?
        var pending = RefreshQueue()
        var monitorGeneration = UUID()
        var debounce: Task<Void, Never>?
        init(_ url: URL) {
            self.url = url; snapshot = ScanSnapshot(rootPath: url.path); scope = url.path
            let incarnation = UUID(); self.incarnation = incarnation
            focus = FocusScanRequests(rootPath: url.path, incarnation: incarnation)
        }
    }
    private var entries: [String: Entry] = [:]
    private var totalStarts = 0
    private let admission: ScanAdmission
    private let scanner: DirectoryScanOperation?
    private let volumeTraversal: ScanVolumeTraversal
    private let monitorFactory: MonitorFactory
    public init(admission: ScanAdmission = .shared, volumeTraversal: ScanVolumeTraversal = .selectedVolume,
                scanner: DirectoryScanOperation? = nil) {
        self.admission = admission; self.scanner = scanner; self.volumeTraversal = volumeTraversal
        monitorFactory = { path, deliver in
            let cursor=DirectoryMonitor.eventCursor()
            return DirectoryMonitorRegistration(create: {
                DirectoryMonitor(path:path,since:cursor ?? DirectoryMonitor.nowCursor) {changes in Task {await deliver(changes)}}
            }, ready: {
                // Journal replay covers registration latency. If no cursor is
                // available, conservatively refresh to close the startup gap.
                Task {await deliver(cursor == nil ? [PathChange(path:path,isDirectory:true,mustRescan:true)] : [])}
            })
        }
    }
    /// Internal dependency seam uses the same generation guard as real FSEvents.
    init(admission: ScanAdmission, scanner: @escaping DirectoryScanOperation, monitorFactory: @escaping MonitorFactory) {
        self.admission = admission; self.scanner = scanner; self.monitorFactory = monitorFactory; volumeTraversal = .selectedVolume
    }
    func pendingQueueObservation(rootPath: String) -> (count: Int, slots: Int, storage: RefreshQueueStorageWitness)? {
        guard let queue = entries[rootPath]?.pending else { return nil }
        return (queue.count, queue.indexSlots, queue.storageWitness)
    }
    public func subscribe(_ input: URL, watching: Bool = true) async -> ScanSubscription {
        let url: URL
        do { url = try await PathIO.canonical(input) }
        catch {
            let channel = AsyncStream<ScanUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
            var snapshot = ScanSnapshot(rootPath: input.standardizedFileURL.path); snapshot.cancelled = error is CancellationError
            channel.continuation.yield(ScanUpdate(snapshot: snapshot, isScanning: false, revision: 0, watchActive: false,
                scope: snapshot.rootPath, progress: nil, schedulingError: snapshot.cancelled ? nil : error.localizedDescription))
            channel.continuation.finish()
            return ScanSubscription(id: UUID(), rootPath: snapshot.rootPath, updates: channel.stream)
        }
        let key = url.path
        let isNew = entries[key] == nil
        let entry = entries[key] ?? Entry(url); entries[key] = entry
        let id = UUID(); let channel = AsyncStream<ScanUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        entry.subscribers[id] = channel.continuation
        channel.continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id, rootPath: key) } }
        if watching { entry.watchers.insert(id) }
        configureMonitor(entry, key: key)
        if isNew { launch(entry, scope: key) } else { channel.continuation.yield(update(entry)) }
        return ScanSubscription(id: id, rootPath: key, updates: channel.stream)
    }
    public func unsubscribe(_ id: UUID, rootPath: String) {
        guard let entry = entries[rootPath] else { return }
        if entry.focus.cancel(owner: id), entry.focusJob?.ownerID == id { cancel(entry) }
        let continuation = entry.subscribers.removeValue(forKey: id)
        continuation?.finish(); entry.watchers.remove(id)
        if entry.subscribers.isEmpty {
            cancel(entry); entry.debounce?.cancel(); entry.monitor = nil; entries[rootPath] = nil
        } else { configureMonitor(entry, key: rootPath); broadcast(entry) }
    }
    public func setWatching(_ enabled: Bool, subscription: ScanSubscription) {
        guard let entry = entries[subscription.rootPath], entry.subscribers[subscription.id] != nil else { return }
        if enabled { entry.watchers.insert(subscription.id) } else { entry.watchers.remove(subscription.id) }
        configureMonitor(entry, key: subscription.rootPath); broadcast(entry)
    }
    public func rescan(rootPath: String, scope: String? = nil) {
        guard let entry = entries[rootPath] else { return }
        entry.focus.reset()
        entry.debounce?.cancel(); entry.pending.removeAll()
        let target = scope.flatMap { SnapshotTree.contains(rootPath, $0) ? $0 : nil } ?? rootPath
        if entry.scanning { entry.restartScope = target; cancel(entry) }
        else { launch(entry, scope: target) }
    }
    public func stop(rootPath: String) {
        guard let entry = entries[rootPath] else { return }
        entry.focus.reset()
        entry.restartScope = nil; cancel(entry); entry.debounce?.cancel(); entry.pending.removeAll()
    }
    /// Explicit opt-in hook for a view/subscription's focused rescan. It never
    /// cancels an active master or another owner's focus job. Overlaps remain
    /// serialized; the scope must be an existing cached directory in this root.
    @discardableResult public func requestFocusRescan(subscription: ScanSubscription, scope: String) -> FocusScanRequest? {
        guard let entry = entries[subscription.rootPath], entry.subscribers[subscription.id] != nil else { return nil }
        let scope = URL(fileURLWithPath: scope).standardizedFileURL.path
        guard SnapshotTree.contains(subscription.rootPath, scope),
              let id = SnapshotTree.nodeID(at: scope, in: entry.snapshot), entry.snapshot.nodes[id].isDirectory else { return nil }
        let request = entry.focus.replace(owner: subscription.id, scope: scope, targetIdentity: entry.snapshot.nodes[id].fileIdentity)
        if entry.focusJob?.ownerID == subscription.id { cancel(entry) }
        if !entry.scanning { launchNextFocus(entry) }
        return request
    }
    public func cancelFocusRescan(_ request: FocusScanRequest) {
        guard let entry = entries[request.rootPath], entry.incarnation == request.rootIncarnation else { return }
        if entry.focus.cancel(request), entry.focusJob == request { cancel(entry) }
    }
    public func cancelFocusRescan(subscription: ScanSubscription) {
        guard let entry = entries[subscription.rootPath], entry.subscribers[subscription.id] != nil else { return }
        if entry.focus.cancel(owner: subscription.id), entry.focusJob?.ownerID == subscription.id { cancel(entry) }
    }
    private func focusTargetIsCurrent(_ request: FocusScanRequest, in entry: Entry) -> Bool {
        guard entry.incarnation == request.rootIncarnation, entry.focus.isCurrent(request),
              entry.subscribers[request.ownerID] != nil, SnapshotTree.contains(entry.url.path, request.scope),
              let id = SnapshotTree.nodeID(at: request.scope, in: entry.snapshot), entry.snapshot.nodes[id].isDirectory else { return false }
        // Missing identities retain path fallback, as in other native/SNS bridges.
        if let identity = request.targetIdentity { return entry.snapshot.nodes[id].fileIdentity == identity }
        return true
    }
    @discardableResult private func launchNextFocus(_ entry: Entry) -> Bool {
        guard !entry.scanning else { return false }
        while let request = entry.focus.takeNext() {
            guard focusTargetIsCurrent(request, in: entry) else { entry.focus.finish(request); continue }
            launch(entry, scope: request.scope, focus: request)
            return true
        }
        return false
    }
    public func setTag(_ mask: Int, path: String, rootPath: String) {
        guard (0...15).contains(mask), let entry = entries[rootPath], SnapshotTree.contains(rootPath, path) else { return }
        guard (entry.tags[path] ?? 0) != mask else { return }
        entry.tags[path] = mask == 0 ? nil : mask
        entry.snapshot.tags = entry.tags; entry.revision += 1; broadcast(entry)
    }
    public func clearTags(scope: String, rootPath: String) {
        guard let entry = entries[rootPath] else { return }
        let tags = entry.tags.filter { !SnapshotTree.contains(scope, $0.key) }
        guard tags != entry.tags else { return }
        entry.tags = tags
        entry.snapshot.tags = entry.tags; entry.revision += 1; broadcast(entry)
    }
    public func statistics() -> EngineStatistics {
        EngineStatistics(roots: entries.count, subscribers: entries.values.reduce(0) { $0 + $1.subscribers.count }, scanStarts: totalStarts, admission: admission.statistics())
    }
    private func configureMonitor(_ entry: Entry, key: String) {
        if entry.watchers.isEmpty {
            entry.monitor = nil; entry.monitorGeneration = UUID()
            entry.debounce?.cancel(); entry.pending.removeAll()
            return
        }
        guard entry.monitor == nil else { return }
        entry.monitorGeneration = UUID(); let monitorGeneration = entry.monitorGeneration
        entry.monitor = monitorFactory(key) { [weak self] changes in
            await self?.changed(changes, rootPath: key, monitorGeneration: monitorGeneration)
        }
    }
    private func changed(_ changes: [PathChange], rootPath: String, monitorGeneration: UUID) {
        guard let entry = entries[rootPath], !entry.watchers.isEmpty,
              entry.monitorGeneration == monitorGeneration else { return }
        for change in changes {
            if change.mustRescan { entry.pending.insert(rootPath); break }
            let path = URL(fileURLWithPath: change.path).standardizedFileURL.path
            guard SnapshotTree.contains(rootPath, path) else { continue }
            if entry.snapshot.volumeCoverage?.exclusions.contains(where: { SnapshotTree.contains($0.path, path) }) == true { continue }
            let parent = path == rootPath ? rootPath : URL(fileURLWithPath: path).deletingLastPathComponent().path
            // A parent refresh handles create/delete/rename without trusting a transient event path.
            entry.pending.insert(parent)
        }
        if changes.isEmpty {broadcast(entry)}
        schedule(entry)
    }
    private func schedule(_ entry: Entry) {
        guard !entry.watchers.isEmpty, !entry.scanning, !entry.pending.isEmpty else { return }
        entry.debounce?.cancel(); let key = entry.url.path
        entry.debounce = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self?.refreshPending(key)
        }
    }
    private func refreshPending(_ key: String) {
        guard let entry = entries[key], !entry.watchers.isEmpty, !entry.scanning,
              var scope = entry.pending.popFirst() else { return }
        // FSEvents may name a newly created or removed folder. Refresh its nearest
        // cached ancestor, rather than combine unrelated requests at their common root.
        while scope != key, SnapshotTree.nodeID(at: scope, in: entry.snapshot).map({ !entry.snapshot.nodes[$0].isDirectory }) ?? true {
            scope = URL(fileURLWithPath: scope).deletingLastPathComponent().path
        }
        if entry.snapshot.issueCount >= 500 { scope = key }
        launch(entry, scope: scope)
    }
    private func launch(_ entry: Entry, scope requestedScope: String, focus: FocusScanRequest? = nil) {
        let scope = ScanWork.requiresRootRefresh(entry.snapshot) ? entry.url.path : requestedScope
        // Focus must not consume watcher requests: an event can arrive while its
        // filesystem read is in flight, or the owning view can cancel it.
        if focus == nil { entry.pending.removeCovered(by: scope) }
        entry.focusJob = focus
        entry.baseline = entry.snapshot.nodes
        entry.generation = UUID(); let generation = entry.generation
        entry.progress = nil
        let control = ScanControl(); entry.control = control; entry.scanning = true; entry.scope = scope
        entry.schedulingError = nil
        totalStarts += 1; broadcast(entry)
        let original = entry.snapshot; let key = entry.url.path
        let anchor = entry.url; let traversal = volumeTraversal
        let scanner: DirectoryScanOperation = self.scanner ?? { url, control, progress, heartbeat in
            DiskScanner.scan(url, control: control, volumeTraversal: traversal, scopeRoot: anchor, progress: progress, heartbeat: heartbeat)
        }
        do {
            entry.job = try admission.submit(control: control, operation: { [weak self] in
                if let focus, !FocusScanTarget.matches(focus, original: original) {
                    return FocusScanTarget.invalidated(original)
                }
                let result = ScanWork.run(original: original, scope: scope, control: control, scanner: scanner,
                    progress: { [weak self] partial in
                        Task { await self?.receive(partial, key: key, generation: generation, completed: false) }
                    }, heartbeat: { [weak self] value in
                        Task { await self?.receiveProgress(value, key: key, generation: generation) }
                    })
                if let focus, !FocusScanTarget.matches(focus, original: original) {
                    return FocusScanTarget.invalidated(original)
                }
                return result
            }, completion: { [weak self] result in
                var snapshot: ScanSnapshot
                switch result {
                case .finished(let value): snapshot = value
                case .cancelledBeforeStart: snapshot = original; snapshot.cancelled = true
                }
                let completed = snapshot
                Task { await self?.receive(completed, key: key, generation: generation, completed: true) }
            })
        } catch {
            entry.scanning = false; entry.control = nil; entry.baseline.removeAll(); entry.job = nil
            if let focus {
                entry.focus.finish(focus); entry.focusJob = nil
                // No worker completion will wake remaining owner intents after
                // admission rejection; reject them together with the visible error.
                entry.focus.reset()
            }
            entry.schedulingError = "스캔 대기열이 가득 찼거나 종료됐습니다. 잠시 후 다시 스캔하세요."
            broadcast(entry)
        }
    }
    private func cancel(_ entry: Entry) {
        entry.control?.cancel()
        if let job = entry.job { admission.cancel(job) }
    }
    private func receiveProgress(_ progress: ScanProgress, key: String, generation: UUID) {
        guard let entry = entries[key], entry.generation == generation, entry.scanning,
              progress.sequence > (entry.progress?.sequence ?? 0) else { return }
        if let focus = entry.focusJob, !focusTargetIsCurrent(focus, in: entry) { return }
        entry.progress = progress
        // A heartbeat is not a new tree revision; views must not refilter it.
        broadcast(entry)
    }
    private func receive(_ snapshot: ScanSnapshot, key: String, generation: UUID, completed: Bool) {
        guard let entry = entries[key], entry.generation == generation else { return }
        // A late progress callback must not overwrite a completed result.
        guard entry.scanning else { return }
        let focus = entry.focusJob
        // A focus job has a frozen baseline and terminal-only publication. Owner
        // replacement/cancel/unsubscribe makes its result obsolete, even if an
        // injected/native operation ignores its cancellation token.
        if focus != nil && !completed { return }
        let acceptsFocus: Bool
        if let focus { acceptsFocus = focusTargetIsCurrent(focus, in: entry) && !snapshot.cancelled }
        else { acceptsFocus = true }
        if acceptsFocus {
            if completed && !snapshot.cancelled {
                entry.tags = TagPolicy.reconcile(entry.tags, previous: entry.baseline, current: snapshot.nodes)
            }
            entry.snapshot = snapshot; entry.snapshot.tags = entry.tags; entry.revision += 1
        }
        if completed {
            entry.scanning = false; entry.control = nil
            entry.baseline.removeAll(); entry.job = nil; entry.focusJob = nil
            if let focus { entry.focus.finish(focus) }
        }
        broadcast(entry)
        if completed {
            if let scope = entry.restartScope { entry.restartScope = nil; launch(entry, scope: scope) }
            else if !launchNextFocus(entry) { schedule(entry) }
        }
    }
    private func update(_ entry: Entry) -> ScanUpdate {
        ScanUpdate(snapshot: entry.snapshot, isScanning: entry.scanning, revision: entry.revision,
                   watchActive: (entry.monitor as? DirectoryWatchState)?.watchActive ?? (entry.monitor != nil), scope: entry.scope, progress: entry.progress, schedulingError: entry.schedulingError)
    }
    private func broadcast(_ entry: Entry) {
        let value = update(entry)
        for continuation in entry.subscribers.values { continuation.yield(value) }
    }
}
