import AppKit
import SwiftUI
import SpaceSnifferCore
import SpaceSnifferAutomation

@MainActor
final class AutomationHub {
    static let shared = AutomationHub()
    private final class WindowEntry {
        weak var store: ScanStore?
        weak var window: NSWindow?
        var observer: NotificationLease?
        let identity = UUID()
        init(_ store: ScanStore, _ window: NSWindow) { self.store = store; self.window = window }
    }
    private var windows: [String: WindowEntry] = [:]
    private let hiddenWindows = ExplicitWindowRetention<NSWindow, ScanStore>()
    var hasExplicitlyHiddenWindows: Bool { hiddenWindows.hasWindows }
    func releaseHiddenWindows() { hiddenWindows.removeAll() }
    private var jobs: [String: JSONValue] = [:]
    private var jobOrder: [String] = []
    private var activeJobs = 0
    private let started = Date()
    func register(_ store: ScanStore, window: NSWindow) {
        if windows[store.automationID]?.window === window { return }
        unregister(store.automationID)
        let entry = WindowEntry(store, window); windows[store.automationID] = entry
        let id = store.automationID; let token = entry.identity
        entry.observer = NotificationLease(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak store] _ in
            Task { @MainActor in
                guard let self, self.windows[id]?.identity == token else { return }
                store?.shutdown(); self.unregister(id)
            }
        })
    }
    func unregister(_ id: String) {
        hiddenWindows.release(id)
        windows[id] = nil
    }
    private func target(_ a: [String: JSONValue]) throws -> (ScanStore, NSWindow) {
        windows = windows.filter { $0.value.store != nil && $0.value.window != nil }
        let id: String
        if let requested = a["window_id"]?.string { id = requested }
        else if let key = windows.first(where: { $0.value.window === NSApp.keyWindow })?.key { id = key }
        else if windows.count == 1 { id = windows.keys.first! }
        else { throw ControlError("window_required", "Pass window_id from app_status; no unique active window") }
        guard let entry = windows[id], let store = entry.store, let window = entry.window else { throw ControlError("not_found", "Window is no longer open") }
        return (store, window)
    }
    private func state(_ s: ScanStore) -> JSONValue {
        let native = windows[s.automationID]?.window
        let presentation = native?.contentView.flatMap { MapCanvas.find(in: $0) }?.presentationStatistics ?? [:]
        let snapshot = s.snapshot
        let queries = s.automationQueries.statistics
        let phase = s.isScanning ? "scanning" : s.scanSchedulingError != nil ? "failed" : s.offline ? "offline" : snapshot == nil ? "idle" : snapshot!.cancelled ? "cancelled" : snapshot!.issueCount > 0 ? "completed_with_issues" : "completed"
        var progress: JSONValue = .null
        if let p = s.scanProgress {
            progress = .object(["sequence": .integer(Int64(p.sequence)), "root": .string(p.rootPath), "current_path": .string(p.currentPath),
                "files": .int(p.fileCount), "folders": .int(p.folderCount), "logical_bytes": .integer(p.logicalBytes), "allocated_bytes": .integer(p.allocatedBytes),
                "visited_folders": .int(p.visitedFolders), "pending_folders": .int(p.pendingFolders), "issues": .int(p.issueCount),
                "overview": p.overview.map { value in
                    func items(_ list: [ScanOverviewItem]) -> JSONValue {
                        .array(list.map { .object(["id": .int($0.id), "path": .string($0.path), "name": .string($0.name),
                            "allocated_bytes": .integer($0.allocatedBytes), "logical_bytes": .integer($0.logicalBytes)]) })
                    }
                    return .object(["source": .string("current_scan_observed"), "observed_nodes": .int(value.observedNodeCount), "folders": items(value.folders), "large_files": items(value.largeFiles)])
                } ?? .null])
        }
        return .object(["window_id": .string(s.automationID), "scan_session_id": .string(s.automationScanSessionID), "phase": .string(phase),
            "overview_painted_at_uptime_ns": s.overviewPaintedAtUptimeNanoseconds.map { .integer(Int64($0)) } ?? .null,
            "root": snapshot.map { .string($0.rootPath) } ?? .null, "scan_scope": s.scanScope.map { .string($0) } ?? .null,
            "volume_traversal": snapshot?.volumeCoverage.map { .string($0.traversal.rawValue) } ?? .null,
            "excluded_boundary_count": snapshot?.volumeCoverage.map { .int($0.excludedCount) } ?? .null,
            "excluded_boundaries": snapshot?.volumeCoverage.map { .array($0.exclusions.map { .object(["path": .string($0.path), "reason": .string($0.reason)]) }) } ?? .null,
            "window_visible": .bool(native?.isVisible ?? false), "window_minimized": .bool(native?.isMiniaturized ?? false),
            "window_retained_hidden": .bool(hiddenWindows.contains(s.automationID)),
            "window_on_active_space": .bool(native?.isOnActiveSpace ?? false),
            "application_hidden": .bool(NSApp.isHidden), "application_active": .bool(NSApp.isActive),
            "window_content_width": native?.contentView.map { .number($0.bounds.width) } ?? .null,
            "window_content_height": native?.contentView.map { .number($0.bounds.height) } ?? .null,
            "window_frame": native.map { .object(["x": .number($0.frame.minX), "y": .number($0.frame.minY), "width": .number($0.frame.width), "height": .number($0.frame.height)]) } ?? .null,
            "window_occluded": .bool(!(native?.occlusionState.contains(.visible) ?? false)),
            "presentation": .object(presentation.mapValues { .int($0) }),
            "query_session": .object(["cursors": .int(queries.cursors), "active_pages": .int(queries.activePages),
                "maximum_cursors": .int(queries.maximumCursors), "maximum_frames_per_cursor": .int(queries.maximumFramesPerCursor),
                "created": .int(queries.created), "reused_contexts": .int(queries.reusedContexts),
                "evicted": .int(queries.evicted), "cancelled": .int(queries.cancelled)]),
            "scan_scheduling_error": s.scanSchedulingError.map { .string($0) } ?? .null,
            "snapshot_revision": .string(s.projectionRevision.uuidString), "projection_pending": .bool(s.projectionPending),
            "snapshot_nodes": .int(snapshot?.nodes.count ?? 0), "snapshot_files": .int(snapshot?.fileCount ?? 0), "snapshot_folders": .int(snapshot?.folderCount ?? 0),
            "root_is_volume": .bool(snapshot?.isVolumeRoot ?? false),
            "snapshot_logical_bytes": snapshot?.nodes.first.map { .integer($0.logicalBytes) } ?? .null,
            "snapshot_allocated_bytes": snapshot?.nodes.first.map { .integer($0.allocatedBytes) } ?? .null,
            "displayed_bytes": .integer(s.displayedBytes), "volume_total_bytes": .integer(snapshot?.volumeTotal ?? 0), "volume_free_bytes": .integer(snapshot?.volumeFree ?? 0),
            "space_accounting": SpaceAccountingPayload.make(snapshot: snapshot, offline: s.offline),
            "issue_count": .int(snapshot?.issueCount ?? 0), "cancelled": .bool(snapshot?.cancelled ?? false), "progress": progress,
            "focus_path": s.focusedNode.map { .string($0.path) } ?? .null, "selected_path": s.selectedNode.map { .string($0.path) } ?? .null,
            "breadcrumbs": .array(s.breadcrumb.map { .string($0.path) }), "history_count": .int(s.history.count), "history_index": .int(s.historyIndex),
            "history_tail": .array(s.history.suffix(50).map { .string($0) }), "can_back": .bool(s.canBack), "can_forward": .bool(s.canForward),
            "filter": .string(s.automationFilterText), "filter_error": s.filterError.map { .string($0) } ?? .null,
            "size_mode": .string(s.sizeMode.rawValue), "show_hidden": .bool(s.showHidden), "detail_depth": .int(s.depth), "list_mode": .bool(s.listMode),
            "watch_requested": .bool(s.liveUpdates), "watch_active": .bool(s.watchActive), "offline": .bool(s.offline),
            "notice": s.notice.map { .string($0) } ?? .null, "coverage_percentage_available": .bool(false)])
    }
    private func context(_ s: ScanStore) throws -> QueryContext {
        guard !s.projectionPending else { throw ControlError("projection_pending", "Wait for projection_pending=false in app_status") }
        guard let context = s.automationContext else { throw ControlError("not_ready", "No readable snapshot yet") }; return context
    }
    private func absolutePath(_ a: [String: JSONValue], _ key: String) throws -> URL {
        let path = try a.requiredString(key)
        guard path.hasPrefix("/"), !path.contains("\0") else { throw ControlError("invalid_argument", "\(key) must be an absolute macOS path") }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
    private func job(_ operation: @escaping @MainActor @Sendable () async throws -> JSONValue) throws -> JSONValue {
        guard activeJobs < 2 else { throw ControlError("busy", "At most two artifact jobs may run concurrently") }
        while jobOrder.count >= 32 {
            guard let index = jobOrder.firstIndex(where: { jobs[$0]?.object?["phase"]?.string != "running" }) else { break }
            jobs[jobOrder.remove(at: index)] = nil
        }
        let id = UUID().uuidString
        activeJobs += 1; jobOrder.append(id); jobs[id] = .object(["job_id": .string(id), "phase": .string("running"), "started_at": .date(Date())])
        Task {
            do { let value = try await operation(); jobs[id] = .object(["job_id": .string(id), "phase": .string("completed"), "result": value, "finished_at": .date(Date())]) }
            catch { jobs[id] = .object(["job_id": .string(id), "phase": .string("failed"), "error": .string(error.localizedDescription), "finished_at": .date(Date())]) }
            activeJobs -= 1
        }
        return .object(["accepted": .bool(true), "job_id": .string(id), "phase": .string("running")])
    }
    func handle(_ request: ControlRequest) async -> ControlResponse {
        do { return ControlResponse(id: request.id, result: try await execute(request.command, request.arguments)) }
        catch { return ControlResponse(id: request.id, error: (error as? ControlError) ?? ControlError("operation_failed", error.localizedDescription)) }
    }
    private func execute(_ command: String, _ a: [String: JSONValue]) async throws -> JSONValue {
        if command == "app_status" {
            windows = windows.filter { $0.value.store != nil && $0.value.window != nil }
            if a["window_id"] != nil { return state(try target(a).0) }
            return .object(["pid": .int(Int(ProcessInfo.processInfo.processIdentifier)), "bundle_id": .string(Bundle.main.bundleIdentifier ?? "unknown"),
                "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
                "controller_started_at": .date(started), "windows": .array(windows.values.compactMap { $0.store.map { state($0) } }),
                "jobs": .array(jobOrder.suffix(10).compactMap { jobs[$0] })])
        }
        if command == "app_resources" {
            let metrics = try await ProcessMetrics.readAsync()
            let stats = await ScanService.shared.statistics()
            let included = await ScanService.includingMountedVolumes.statistics()
            let telemetry = WorkerTelemetry.shared.snapshot().mapValues { sample in JSONValue.object([
                "runs": .int(sample.runs), "main_thread_runs": .int(sample.mainThreadRuns), "submitted": .int(sample.submitted),
                "started": .int(sample.started), "completed": .int(sample.completed), "cancelled": .int(sample.cancelled),
                "failed": .int(sample.failed), "coalesced": .int(sample.coalesced), "stale_drops": .int(sample.staleDrops),
                "active": .int(sample.active), "peak_active": .int(sample.peakActive), "timed_calls": .int(sample.timedCalls),
                "total_seconds": .number(Double(sample.totalNanoseconds) / 1e9), "maximum_seconds": .number(Double(sample.maximumNanoseconds) / 1e9),
                "recent_seconds": .array(sample.recentNanoseconds.map { .number(Double($0) / 1e9) }),
                "queue_samples": .int(sample.queueSamples), "queue_seconds": .number(Double(sample.queueNanoseconds) / 1e9),
                "maximum_queue_seconds": .number(Double(sample.maximumQueueNanoseconds) / 1e9), "sampled_thread_ids": .array(sample.threadIDs.map { .string(String($0)) })]) }
            let admission = stats.admission
            let canvases = CanvasLifetime.shared.snapshot()
            let scratch = ScratchResources.statistics()
            return .object(["process": metrics, "engine": .object(["cached_roots": .int(stats.roots + included.roots), "subscribers": .int(stats.subscribers + included.subscribers), "scan_starts": .int(stats.scanStarts + included.scanStarts),
                "scan_limit": .int(admission.limit), "active_scans": .int(admission.active), "queued_scans": .int(admission.queued),
                "scan_queue_capacity": .int(admission.capacity), "peak_active_scans": .int(admission.peakActive),
                "admitted_scans": .int(admission.started), "finished_scan_workers": .int(admission.finished),
                "cancelled_queued_scans": .int(admission.cancelledBeforeStart), "rejected_scans": .int(admission.rejected)]), "workers": .object(telemetry),
                "canvases": .object(["created": .int(canvases.created), "released": .int(canvases.released), "live": .int(canvases.created - canvases.released), "explicitly_hidden_windows": .int(hiddenWindows.count)]),
                "scratch": .object(["retained_idle_bytes": .int(scratch.retainedBytes), "charged_idle_bytes": .int(scratch.chargedBytes),
                    "idle_limit_bytes": .int(scratch.limit), "owners": .int(scratch.owners), "active": .int(scratch.active),
                    "peak_active": .int(scratch.peakActive), "hits": .int(scratch.hits), "misses": .int(scratch.misses),
                    "evicted_bytes": .int(scratch.evictedBytes), "pressure_events": .int(scratch.pressureEvents)])])
        }
        if command == "volumes_list" {
            let volumes = try await ArtifactWorker.shared.volumes()
            return .object(["volumes": .array(volumes.map { .object(["name": .string($0.name), "path": .string($0.url.path)]) })])
        }
        if command == "volume_info" {
            let url = try absolutePath(a, "path")
            let value = try await PathIO.volume(url)
            return .object(["path": .string(url.path), "total_bytes": .integer(value.total), "free_bytes": .integer(value.free),
                "system_used_estimate_bytes": .integer(max(0, value.total - value.free)), "accounting_note": .string("Filesystem values; pathname scan sums can differ due to APFS sharing, snapshots, excluded symlinks and access errors.")])
        }
        if command == "task_status" {
            let id = try a.requiredString("job_id")
            guard let value = jobs[id] else { throw ControlError("not_found", "Job not found or evicted from the last 32 jobs") }; return value
        }
        let (store, window) = try target(a)
        switch command {
        case "scan_start":
            if store.isScanning && a["replace"]?.boolean != true { throw ControlError("busy", "Scan is running; use scan_stop or explicitly set replace=true") }
            let url = try absolutePath(a, "path")
            let valid = try await PathIO.isDirectory(url)
            guard valid else { throw ControlError("not_found", "Scan path is not an accessible directory") }
            if store.isScanning && a["replace"]?.boolean != true { throw ControlError("busy", "Scan started while validating the path; retry with explicit replacement if intended") }
            if let watching = a["watching"]?.boolean { store.liveUpdates = watching }
            if let include = a["include_mounted_volumes"]?.boolean { store.setVolumeTraversal(include ? .allVolumes : .selectedVolume, restart: false) }
            store.start(url)
            return .object(["accepted": .bool(true), "window_id": .string(store.automationID), "scan_session_id": .string(store.automationScanSessionID), "path": .string(url.path)])
        case "scan_stop": store.stop(); return .object(["accepted": .bool(true), "phase": .string("stop_requested")])
        case "scan_rescan":
            guard !store.offline, !store.isScanning else { throw ControlError("busy", "Rescan requires an idle live scan") }
            if let path = a["path"]?.string {
                let c = try context(store); let id = try await Task.detached { try c.nodeID(path: path) }.value
                guard c.revision == store.projectionRevision.uuidString else { throw ControlError("stale_revision", "Snapshot changed; retry") }
                guard !store.offline, !store.isScanning else { throw ControlError("busy", "Rescan requires an idle live scan") }
                guard c.snapshot.nodes[id].isDirectory else { throw ControlError("invalid_argument", "Rescan path must be a folder") }
                guard await store.automationRescan(scope: path) else { throw ControlError("stale_revision", "Focused rescan target or subscription changed; retry") }
            } else { store.rescan() }
            return .object(["accepted": .bool(true)])
        case "node_info", "tree_children", "query_nodes", "largest_nodes", "scan_issues":
            let c = try context(store)
            let queries = store.automationQueries
            let queryEpoch = queries.epoch
            do {
                return try await QueryExecution.run {
                    if command == "query_nodes", a["traversal"]?.string == "subtree" { return try queries.query(context: c, arguments: a, epoch: queryEpoch) }
                    return try c.query(command: command, arguments: a)
                }
            } catch is CancellationError { throw ControlError("cancelled", "Query cancelled; restart pagination if needed") }
        case "view_set":
            let windowState = a["window_state"]?.string
            if let windowState, !["normal", "minimized", "hidden"].contains(windowState) { throw ControlError("invalid_argument", "Unknown window_state") }
            let contentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
            let width = a["width"] == nil ? contentSize.width : CGFloat(try a.boundedInt("width", default: 1340, range: 640...4096))
            let height = a["height"] == nil ? contentSize.height : CGFloat(try a.boundedInt("height", default: 860, range: 480...4096))
            if a["action"] != nil || a["expression"] != nil { _ = try context(store) }
            if let text = a["expression"]?.string { _ = try await Task.detached { try ScanFilter(text) }.value }
            if let mode = a["size_mode"]?.string, SizeMode(rawValue: mode) == nil { throw ControlError("invalid_argument", "size_mode must be logical or allocated") }
            let depth = try a.boundedInt("depth", default: store.depth, range: 1...6)
            if a["path"] != nil && a["action"] != nil { throw ControlError("invalid_argument", "Specify path or action, not both") }
            if let action = a["action"]?.string, !["up", "back", "forward", "root"].contains(action) { throw ControlError("invalid_argument", "Unknown navigation action") }
            let navigationID: Int?
            if let path = a["path"]?.string {
                let c = try context(store); let id = try await Task.detached { try c.nodeID(path: path) }.value
                guard c.revision == store.projectionRevision.uuidString else { throw ControlError("stale_revision", "Snapshot changed; retry") }
                guard c.snapshot.nodes[id].isDirectory else { throw ControlError("invalid_argument", "View path must be a folder") }
                navigationID = id
            } else { navigationID = nil }
            store.updateView {
            if let navigationID { store.navigate(navigationID) }
            switch a["action"]?.string {
            case "up": store.up()
            case "back": store.back()
            case "forward": store.forward()
            case "root": store.navigate(0)
            default: break
            }
            if let mode = a["size_mode"]?.string { store.sizeMode = SizeMode(rawValue: mode)! }
            if let hidden = a["show_hidden"]?.boolean { store.showHidden = hidden }
            if let watching = a["watching"]?.boolean { store.liveUpdates = watching }
            if let list = a["list_mode"]?.boolean { store.listMode = list }
            store.depth = depth
            if let text = a["expression"]?.string { store.filterText = text; store.applyFilter() }
            }
            if a["width"] != nil || a["height"] != nil { window.setContentSize(CGSize(width: width, height: height)) }
            switch windowState {
            case "normal": NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true); window.deminiaturize(nil); window.makeKeyAndOrderFront(nil); hiddenWindows.release(store.automationID)
            case "minimized": window.miniaturize(nil); hiddenWindows.release(store.automationID)
            case "hidden": hiddenWindows.retain(store.automationID, window: window, model: store); window.orderOut(nil)
            default: break
            }
            return .object(["accepted": .bool(true), "state": state(store)])
        case "node_tag":
            let c = try context(store); let path = try a.requiredString("path")
            let id = try await Task.detached { try c.nodeID(path: path) }.value
            guard c.revision == store.projectionRevision.uuidString else { throw ControlError("stale_revision", "Snapshot changed; retry") }
            let color = try a.boundedInt("color", default: 0, range: 0...4)
            store.tag(id, color: color); return .object(["accepted": .bool(true), "path": .string(path)])
        case "snapshot_load":
            let url = try absolutePath(a, "path")
            let codePage = try a["legacy_code_page"].map { _ in UInt32(try a.boundedInt("legacy_code_page", default: 1, range: 1...65535)) }
            let rootIndex = try a["root_index"].map { _ in try a.boundedInt("root_index", default: 0, range: 0...Int(Int32.max)) }
            if a["inspect_only"]?.boolean == true {
                return try job {
                    let roots = try await ArtifactWorker.shared.inspectRoots(url, legacyCodePage: codePage)
                    return .object(["roots": .array(roots.map { root in .object([
                        "root_index": .int(root.index), "path": .string(root.path), "files": .int(root.files), "folders": .int(root.folders),
                        "logical_bytes": .integer(root.logicalBytes), "allocated_bytes": .integer(root.allocatedBytes)]) })])
                }
            }
            if store.isScanning && a["replace"]?.boolean != true { throw ControlError("busy", "Scan running; use replace=true explicitly") }
            return try job { try await store.loadSnapshotAwaiting(url, legacyCodePage: codePage, rootIndex: rootIndex); return .object(["loaded": .bool(true), "projection_pending": .bool(store.projectionPending)]) }
        case "report_export" where a["inspect_only"]?.boolean == true:
            let url = try absolutePath(a, "configuration_path")
            let pages = try configurationCodePages(a)
            let selected = try a["configuration_index"].map { _ in try a.boundedInt("configuration_index", default: 0, range: 0...Int(Int32.max)) }
            return try job {
                let inspection = try await ArtifactWorker.shared.inspectConfiguration(url, legacyCodePage: pages.legacy, xmlTextCodePage: pages.xml)
                return try ConfigurationPayload.inspection(inspection, selectedIndex: selected)
            }
        case "snapshot_save", "report_export":
            let c = try context(store); let output = try absolutePath(a, "output")
            let configurationKeys = ["configuration_path", "configuration_index", "config_legacy_code_page", "config_xml_code_page", "max_output_bytes"]
            guard command == "report_export" || configurationKeys.allSatisfy({ a[$0] == nil }) else {
                throw ControlError("invalid_argument", "Configuration options apply only to report_export")
            }
            let configurationURL = try a["configuration_path"].map { _ in try absolutePath(a, "configuration_path") }
            guard configurationURL != nil || configurationKeys.dropFirst().allSatisfy({ a[$0] == nil }) else {
                throw ControlError("invalid_argument", "Configuration options require configuration_path")
            }
            let pages = try configurationCodePages(a)
            let configurationIndex = try a["configuration_index"].map { _ in try a.boundedInt("configuration_index", default: 0, range: 0...Int(Int32.max)) }
            let maximumBytes = try a.boundedInt("max_output_bytes", default: 1_073_741_824, range: 1...1_073_741_824)
            let ext = command == "snapshot_save" ? "sns" : "txt"
            guard output.pathExtension.lowercased() == ext else { throw ControlError("invalid_argument", "Output extension must be .\(ext)") }
            let exists = try await PathIO.exists(output)
            guard !exists else { throw ControlError("already_exists", "Output exists; choose a new path") }
            return try job {
                if command == "snapshot_save" {
                    try await ArtifactWorker.shared.save(c.snapshot, filter: c.filter, showHidden: c.showHidden, root: c.focus, to: output, replaceExisting: false)
                } else if let configurationURL {
                    let inspection = try await ArtifactWorker.shared.inspectConfiguration(configurationURL, legacyCodePage: pages.legacy, xmlTextCodePage: pages.xml)
                    let selected = try inspection.selectingExport(configurationIndex)
                    let options = ConfiguredExportOptions(configuration: selected, filter: c.filter, mode: c.mode,
                        showHidden: c.showHidden, root: c.focus, formatting: MacExportFormatting.localized(), maximumOutputBytes: Int64(maximumBytes))
                    _ = try await ArtifactWorker.shared.exportConfigured(c.snapshot, options: options, to: output, replaceExisting: false)
                } else {
                    guard configurationIndex == nil else { throw ControlError("invalid_argument", "configuration_index requires configuration_path") }
                    try await ArtifactWorker.shared.export(c.snapshot, filter: c.filter, mode: c.mode, showHidden: c.showHidden, root: c.focus, to: output, replaceExisting: false)
                }
                return .object(["output": .string(output.path), "revision": .string(c.revision)])
            }
        case "view_capture":
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while store.projectionPending {
                if ProcessInfo.processInfo.systemUptime >= deadline { throw ControlError("projection_pending", "Wait for the current projection") }
                try await Task.sleep(for: .milliseconds(10))
            }
            await Task.yield()
            guard let view = window.contentView else { throw ControlError("not_ready", "Window has no content") }
            view.layoutSubtreeIfNeeded()
            let canvas = MapCanvas.find(in: view)
            do { try await canvas?.prepareCapture() }
            catch MapCanvas.CaptureError.pending { throw ControlError("projection_pending", "Wait for the latest projection and geometry") }
            catch { throw ControlError("not_ready", "Window closed while preparing capture") }
            defer { canvas?.finishCapture() }
            let bounds = view.bounds
            let scale = min(1, 1600 / max(1, bounds.width), 1200 / max(1, bounds.height))
            let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
            guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw ControlError("capture_failed", "Bitmap allocation failed") }
            image.size = bounds.size; view.cacheDisplay(in: bounds, to: image)
            guard let png = image.representation(using: .png, properties: [:]) else { throw ControlError("capture_failed", "PNG encoding failed") }
            return .object(["image": .object(["data": .string(png.base64EncodedString()), "mimeType": .string("image/png")]),
                "window_id": .string(store.automationID), "width": .int(width), "height": .int(height)])
        default: throw ControlError("unknown_command", command)
        }
    }
    private func configurationCodePages(_ arguments: [String: JSONValue]) throws -> (legacy: UInt32?, xml: UInt32?) {
        func page(_ key: String) throws -> UInt32? {
            try arguments[key].map { _ in UInt32(try arguments.boundedInt(key, default: 1, range: 1...65535)) }
        }
        return try (page("config_legacy_code_page"), page("config_xml_code_page"))
    }
}

struct AutomationWindowAttachment: NSViewRepresentable {
    let store: ScanStore
    func makeNSView(context: Context) -> Attachment { Attachment(store: store) }
    func updateNSView(_ view: Attachment, context: Context) {}
    final class Attachment: NSView {
        let store: ScanStore
        init(store: ScanStore) { self.store = store; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { AutomationHub.shared.register(store, window: window) }
        }
    }
}
