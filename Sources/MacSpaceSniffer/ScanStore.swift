import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SpaceSnifferCore
import SpaceSnifferAutomation

@MainActor
final class ScanStore: ObservableObject {
    @Published var volumes: [DiskVolume] = []
    @Published var snapshot: ScanSnapshot?
    @Published var weights: [Int64] = []
    var geometrySource: GeometrySource?
    private var trackedHistoryIDs: [String: Int] = [:]
    @Published var focus = 0
    @Published var selected: Int?
    @Published var isScanning = false
    @Published var offline = false
    @Published var filterText = ""
    @Published var filterError: String?
    @Published var notice: String?
    @Published var sizeMode: SizeMode = .allocated { didSet { if oldValue != sizeMode { recalculate() } } }
    @Published var showHidden = true { didSet { if oldValue != showHidden { recalculate() } } }
    @Published var depth = 3
    @Published var colorByType = true
    @Published var liveUpdates = true { didSet { if let subscription { let service = scanService; let enabled = liveUpdates; Task { await service.setWatching(enabled, subscription: subscription) } } } }
    @Published private(set) var volumeTraversal: ScanVolumeTraversal = .selectedVolume
    @Published var projectionRevision = UUID() { didSet { automationQueries.reset() } }
    @Published var projectionPending = false
    @Published var scanScope: String?
    @Published var scanSchedulingError: String?
    let automationID = UUID().uuidString
    let automationQueries = SubtreeQuerySession()
    var automationScanSessionID: String { generation.uuidString }
    var automationFilterText: String { requestedFilterText }
    var automationContext: QueryContext? {
        guard let snapshot, !snapshot.nodes.isEmpty, weights.count == snapshot.nodes.count else { return nil }
        return QueryContext(snapshot: snapshot, weights: weights, filter: filter, mode: sizeMode, showHidden: showHidden, revision: projectionRevision.uuidString, focus: focus, selection: selected)
    }
    @Published var watchActive = false
    @Published var scanProgress: ScanProgress?
    private(set) var overviewPaintedAtUptimeNanoseconds: UInt64?
    func markOverviewPainted(session: String) {
        guard session == automationScanSessionID, isScanning, scanProgress?.overview != nil,
              overviewPaintedAtUptimeNanoseconds == nil else { return }
        overviewPaintedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    }
    @Published var showIssues = false
    @Published var listMode = false
    @Published var history: [String] = []
    @Published var historyIndex = -1
    private var generation = UUID()
    private var renderGeneration = UUID()
    private var artifactGeneration = UUID()
    private var snapshotLoadControl: ScanControl?
    private(set) var projectionSource: ProjectionSource?
    private var tags: [String: Int] = [:]
    private var subscription: ScanSubscription?
    private var scanTask: Task<Void, Never>?
    private var preservedFocus: String?
    private var acceptedEngineRevision: UInt64?
    private var completedRootPath: String?
    private var scanService: ScanService
    private let injectedScanService: ScanService?
    private var requestedRoot: URL?
    private var filter = try! ScanFilter("")
    private var requestedFilterText = ""
    private var projectedChildren: [Int] = []
    private let projectionSession = ProjectionSession()
    private var viewChangeDepth = 0
    private var projectionRequested = false

    init(scanService: ScanService? = nil) { injectedScanService = scanService; self.scanService = scanService ?? .shared }

    func setVolumeTraversal(_ traversal: ScanVolumeTraversal, restart: Bool = true) {
        guard volumeTraversal != traversal else { return }
        volumeTraversal = traversal
        if restart, !offline, let requestedRoot { start(requestedRoot) }
    }

    var focusedNode: DiskNode? { node(focus) }
    var selectedNode: DiskNode? { selected.flatMap { node($0) } }
    var displayedBytes: Int64 {
        if isScanning, focus == 0, requestedFilterText.isEmpty, showHidden,
           let progress = scanProgress, progress.rootPath == snapshot?.rootPath {
            return sizeMode == .allocated ? progress.allocatedBytes : progress.logicalBytes
        }
        return weights.indices.contains(focus) ? weights[focus] : 0
    }
    var breadcrumb: [DiskNode] {
        guard let snapshot, snapshot.nodes.indices.contains(focus) else { return [] }
        var result: [DiskNode] = []; var cursor: Int? = focus
        while let id = cursor { result.append(snapshot.nodes[id]); cursor = snapshot.nodes[id].parent }
        return result.reversed()
    }
    var visibleChildren: [Int] { projectedChildren }
    var canBack: Bool { historyIndex > 0 }
    var canForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }
    func node(_ id: Int) -> DiskNode? {
        guard let snapshot, snapshot.nodes.indices.contains(id) else { return nil }; return snapshot.nodes[id]
    }
    func loadVolumes() {
        Task {
            do { volumes = try await ArtifactWorker.shared.volumes() }
            catch { notice = error.localizedDescription }
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "스캔 시작"; panel.message = "사용량을 분석할 폴더 또는 볼륨을 선택하세요."
        if panel.runModal() == .OK, let url = panel.url { start(url) }
    }
    func start(_ url: URL, preserve: Bool = false) {
        disconnect()
        requestedRoot = url
        scanService = injectedScanService ?? (volumeTraversal == .allVolumes ? .includingMountedVolumes : .shared)
        generation = UUID(); let token = generation
        renderGeneration = UUID(); projectionSession.reset(); projectionPending = false
        preservedFocus = preserve ? focusedNode?.path : nil
        if !preserve {
            geometrySource = nil; trackedHistoryIDs = [:]
            snapshot = nil; projectionSource = nil; weights = []; selected = nil; focus = 0; projectedChildren = []
            history = []; historyIndex = -1; tags = [:]; filterText = ""; requestedFilterText = ""; filter = try! ScanFilter("")
        }
        offline = false; isScanning = true; notice = nil; filterError = nil
        let watching = liveUpdates; let service = scanService
        scanTask = Task { [weak self] in
            let lease = await service.subscribe(url, watching: watching)
            guard !Task.isCancelled, let self, self.generation == token else {
                await service.unsubscribe(lease.id, rootPath: lease.rootPath); return
            }
            self.subscription = lease
            for await update in lease.updates {
                guard !Task.isCancelled, self.generation == token else { break }
                self.isScanning = update.isScanning; self.watchActive = update.watchActive
                self.scanProgress = update.progress; self.scanScope = update.scope
                if let oldError = self.scanSchedulingError, self.notice == oldError, update.schedulingError == nil { self.notice = nil }
                self.scanSchedulingError = update.schedulingError
                let retainsCompleted = update.snapshot.cancelled && self.completedRootPath == update.snapshot.rootPath &&
                    self.projectionSource?.snapshot.nodes.sharesStorage(with: update.snapshot.nodes) == true
                if self.acceptedEngineRevision != update.revision {
                    self.acceptedEngineRevision = update.revision
                    if !update.isScanning {
                        if !update.snapshot.cancelled, update.snapshot.issueCount == 0,
                           update.schedulingError == nil, !update.snapshot.nodes.isEmpty {
                            self.completedRootPath = update.snapshot.rootPath
                        } else if !retainsCompleted { self.completedRootPath = nil }
                    }
                    // Native 0x455be0 removes unobserved rescan children only
                    // after enumeration completes. A temporary absent path in
                    // a Mac immutable partial tree is not a confirmed deletion.
                    // Keep the complete presentation during a same-root rescan;
                    // heartbeat/errors continue above and tags remain current.
                    if update.isScanning, self.completedRootPath == update.snapshot.rootPath,
                       self.projectionSource?.snapshot.rootPath == update.snapshot.rootPath {
                        if self.tags != update.snapshot.tags {
                            self.tags = update.snapshot.tags; self.refreshTagSource(); self.recalculate()
                        }
                    } else { self.accept(update.snapshot) }
                }
                if let error = update.schedulingError { self.notice = error }
                else if !update.isScanning {
                    if update.snapshot.nodes.isEmpty { self.notice = "폴더를 읽지 못했습니다. 경로와 접근 권한을 확인하세요." }
                    else if update.snapshot.cancelled {
                        self.notice = retainsCompleted ? "재스캔을 중지했습니다. 이전에 완료한 결과를 유지합니다." : "스캔을 중지했습니다. 현재까지 읽은 결과를 표시합니다."
                    }
                }
            }
        }
    }
    private func disconnect() {
        snapshotLoadControl?.cancel(); snapshotLoadControl = nil
        projectionSession.reset()
        scanTask?.cancel(); scanTask = nil; watchActive = false
        acceptedEngineRevision = nil; scanProgress = nil; scanScope = nil; scanSchedulingError = nil
        overviewPaintedAtUptimeNanoseconds = nil
        completedRootPath = nil
        if let lease = subscription {
            let service = scanService
            Task { await service.unsubscribe(lease.id, rootPath: lease.rootPath) }
        }
        subscription = nil
    }
    private func accept(_ input: ScanSnapshot) {
        tags = input.tags; projectionSource = ProjectionSource(input)
        recalculate()
    }
    func applyFilter() { requestedFilterText = filterText; recalculate() }
    func clearFilter() { filterText = ""; applyFilter() }
    /// One UI intent may change navigation, mode and filter together.
    /// Coalesce only the requests; the projection session owns calculation/cache policy.
    func updateView(_ change: () -> Void) {
        viewChangeDepth += 1
        defer {
            viewChangeDepth -= 1
            if viewChangeDepth == 0, projectionRequested { projectionRequested = false; recalculate() }
        }
        change()
    }
    private func recalculate() {
        if viewChangeDepth > 0 { projectionRequested = true; return }
        guard let source = projectionSource else { return }
        projectionPending = true
        let token = UUID(); renderGeneration = token
        let request = ProjectionRequest(source: source, filterText: requestedFilterText, fallbackFilter: filter,
            mode: sizeMode, showHidden: showHidden, focusPath: preservedFocus ?? focusedNode?.path,
            selectionPath: selectedNode?.path, previous: snapshot, history: history, historyIndex: historyIndex)
        projectionSession.submit(request) { [weak self] outcome in self?.publish(outcome, token: token) }
    }
    private func publish(_ outcome: ProjectionOutcome, token: UUID) {
        guard renderGeneration == token else { return }
        guard selectedNode?.path == outcome.requestedSelectionPath else { recalculate(); return }
        let value = outcome.projection
        geometrySource = value.geometrySource
        trackedHistoryIDs = value.trackedNodeIDs
        snapshot = value.snapshot; weights = value.weights; focus = value.focus; selected = value.selection
        preservedFocus = focusedNode?.path
        history = value.history; historyIndex = value.historyIndex
        projectedChildren = value.children; filter = outcome.filter; filterError = outcome.error
        projectionRevision = UUID(); projectionPending = false
    }
    func stop() {
        if let subscription { let service = scanService; Task { await service.stop(rootPath: subscription.rootPath) } }
        else { generation = UUID(); scanTask?.cancel(); scanTask = nil; isScanning = false }
    }
    func rescan() {
        guard !offline, let subscription else { return }
        let service = scanService
        Task { await service.rescan(rootPath: subscription.rootPath) }
    }
    func automationRescan(scope: String) async -> Bool {
        guard !offline, let subscription else { return false }
        if scope == subscription.rootPath {
            await scanService.rescan(rootPath: subscription.rootPath)
            return true
        }
        return await scanService.requestFocusRescan(subscription: subscription, scope: scope) != nil
    }
    func rescanFocus() {
        guard !offline, let subscription, let path = focusedNode?.path else { return }
        let service = scanService
        Task { await service.requestFocusRescan(subscription: subscription, scope: path) }
    }
    func navigate(_ id: Int, addHistory: Bool = true) {
        guard let node = node(id), node.isDirectory else { selected = id; return }
        focus = id; selected = nil; preservedFocus = node.path; projectedChildren = []
        if addHistory && (!history.indices.contains(historyIndex) || history[historyIndex] != node.path) {
            history = Array(history.prefix(historyIndex + 1)); history.append(node.path); historyIndex = history.count - 1
        }
        recalculate()
    }
    func back() { moveHistory(-1) }
    func forward() { moveHistory(1) }
    private func moveHistory(_ delta: Int) {
        let next = historyIndex + delta
        guard history.indices.contains(next), let snapshot else { return }
        let path = history[next]
        let cached = trackedHistoryIDs[path].flatMap { id in node(id)?.path == path ? id : nil }
        guard let id = cached ?? SnapshotTree.nodeID(at: path, in: snapshot) else { return }
        historyIndex = next; navigate(id, addHistory: false)
    }
    func up() { if let parent = focusedNode?.parent { navigate(parent) } }
    func tag(_ id: Int, color: Int) {
        guard let node = node(id) else { return }
        // REA: FormKeyDown 0x42f0a0 replaces the own tag; pressing the same color clears it.
        let bit = color == 0 ? 0 : 1 << (color - 1)
        let mask = (tags[node.path] ?? 0) == bit ? 0 : bit
        if let subscription, !offline {
            let service = scanService
            Task { await service.setTag(mask, path: node.path, rootPath: subscription.rootPath) }
        } else { tags[node.path] = mask == 0 ? nil : mask; refreshTagSource(); recalculate() }
    }
    func clearTagsInFocus() {
        guard let scope = focusedNode?.path else { return }
        if let subscription, !offline {
            let service = scanService
            Task { await service.clearTags(scope: scope, rootPath: subscription.rootPath) }
        } else {
            tags = tags.filter { !SnapshotTree.contains(scope, $0.key) }; refreshTagSource(); recalculate()
        }
    }
    private func refreshTagSource() {
        guard var input = projectionSource?.snapshot ?? snapshot else { return }
        input.tags = tags; projectionSource = ProjectionSource(input)
    }
    func effectiveTag(_ id: Int) -> Int {
        guard let node = node(id) else { return 0 }
        // REA manual §7 + node getTag: display own color; ancestors affect matching only.
        let mask = tags[node.path] ?? 0
        return (1...4).first { mask & (1 << ($0 - 1)) != 0 } ?? 0
    }
    func zoomTarget(_ id: Int) {
        guard let target = node(id) else { return }
        // REA pnlGraphDblClick 0x42c590: a file zooms its containing folder; it is never launched here.
        if target.isDirectory { navigate(id) }
        else if let parent = target.parent { navigate(parent) }
    }
    func reveal(_ id: Int) {
        guard !offline, let node = node(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
    }
    func open(_ id: Int) {
        guard !offline, let node = node(id) else { return }
        if node.isDirectory { navigate(id) } else { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) }
    }
    func preview(_ id: Int) {
        guard !offline, let node = node(id) else { return }
        QuickLook.shared.show(URL(fileURLWithPath: node.path))
    }
    func copyPath(_ id: Int) {
        guard let node = node(id) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.path, forType: .string)
    }
    func trash(_ id: Int) {
        guard !offline, !isScanning, id != 0, let node = node(id) else { return }
        let alert = NSAlert(); alert.messageText = "‘\(node.name)’을(를) 휴지통으로 이동할까요?"
        alert.informativeText = "\(node.path)\nFinder의 휴지통에서 복원할 수 있습니다."
        alert.alertStyle = .warning; alert.addButton(withTitle: "휴지통으로 이동"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do { try await ArtifactWorker.shared.trash(URL(fileURLWithPath: node.path)); selected = nil; rescan() }
            catch { notice = error.localizedDescription }
        }
    }
    func exportFileList() {
        guard let snapshot else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "File list.txt"
        panel.message = "원본 Simple file list 형식으로 현재 필터의 파일 경로를 저장합니다."
        if panel.runModal() == .OK, let url = panel.url {
            let filter = filter; let mode = sizeMode; let hidden = showHidden; let root = focus
            Task {
                do { try await ArtifactWorker.shared.export(snapshot, filter: filter, mode: mode, showHidden: hidden, root: root, to: url) }
                catch { notice = error.localizedDescription }
            }
        }
    }
    func saveSnapshot() {
        guard let snapshot else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "sns") ?? .data]; panel.nameFieldStringValue = "disk-snapshot.sns"
        if panel.runModal() == .OK, let url = panel.url {
            let filter = filter; let hidden = showHidden; let root = focus
            Task {
                do {
                    try await ArtifactWorker.shared.save(snapshot, filter: filter, showHidden: hidden, root: root, to: url)
                }
                catch { notice = error.localizedDescription }
            }
        }
    }
    func loadSnapshot() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "sns") ?? .data, UTType(filenameExtension: "du") ?? .plainText]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { loadSnapshot(url) }
    }
    func loadSnapshot(_ url: URL) {
        let requestGeneration = generation
        Task {
            var codePage: UInt32?, rootIndex: Int?
            while requestGeneration == generation {
                do { try await loadSnapshotAwaiting(url, legacyCodePage: codePage, rootIndex: rootIndex); return }
                catch SNSSnapshot.FormatError.legacyCodePageRequired, WindowsLegacyText.DecodeError.codePageRequired {
                    guard requestGeneration == generation, let choice = SnapshotOpenOptions.legacyCodePage() else { return }
                    codePage = choice
                } catch SNSSnapshot.FormatError.rootSelectionRequired, DUSnapshot.FormatError.rootSelectionRequired {
                    do {
                        let roots = try await ArtifactWorker.shared.inspectRoots(url, legacyCodePage: codePage)
                        guard requestGeneration == generation, let choice = SnapshotOpenOptions.root(roots) else { return }
                        rootIndex = choice
                    } catch { if requestGeneration == generation { notice = "스냅샷을 열 수 없습니다: \(error.localizedDescription)" }; return }
                } catch is CancellationError { return }
                catch { if requestGeneration == generation { notice = "스냅샷을 열 수 없습니다: \(error.localizedDescription)" }; return }
            }
        }
    }
    func loadSnapshotAwaiting(_ url: URL, legacyCodePage: UInt32? = nil, rootIndex: Int? = nil) async throws {
        let token = generation; artifactGeneration = UUID(); let artifactToken = artifactGeneration
        snapshotLoadControl?.cancel()
        let control = ScanControl(); snapshotLoadControl = control
        defer { if artifactToken == artifactGeneration { snapshotLoadControl = nil } }
        let result = try await ArtifactWorker.shared.load(url, legacyCodePage: legacyCodePage, rootIndex: rootIndex, control: control)
        guard token == generation, artifactToken == artifactGeneration else { throw CancellationError() }
        disconnect(); generation = UUID(); renderGeneration = UUID(); projectionSession.reset()
        isScanning = false; offline = true
        tags = result.tags; snapshot = nil; projectionSource = nil; geometrySource = nil; trackedHistoryIDs = [:]; selected = nil; focus = 0; preservedFocus = nil
        history = []; historyIndex = -1; filterText = ""; requestedFilterText = ""; filter = try! ScanFilter(""); filterError = nil
        notice = "저장된 스냅샷입니다. 파일 작업과 자동 갱신은 새 스캔 후 사용할 수 있습니다."
        accept(result)
    }
    func shutdown() {
        automationQueries.shutdown()
        generation = UUID(); renderGeneration = UUID(); artifactGeneration = UUID(); disconnect(); projectionSession.shutdown()
        projectionSource = nil; geometrySource = nil
        snapshot = nil; weights = []; tags = [:]; projectedChildren = []; history = []; historyIndex = -1
        selected = nil; preservedFocus = nil; projectionPending = false; isScanning = false
        trackedHistoryIDs = [:]
    }
}
