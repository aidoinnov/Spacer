import SwiftUI
import AppKit
import SpaceSnifferCore

final class CanvasLifetime: @unchecked Sendable {
    static let shared = CanvasLifetime()
    private let lock = NSLock()
    private var created = 0; private var released = 0
    func add() { lock.withLock { created += 1 } }
    func remove() { lock.withLock { released += 1 } }
    func snapshot() -> (created: Int, released: Int) { lock.withLock { (created, released) } }
}

extension FileCategory {
    var nsColor: NSColor {
        switch self {
        case .folder: NSColor(srgbRed: 0.22, green: 0.47, blue: 0.53, alpha: 1)
        case .image: NSColor(srgbRed: 0.55, green: 0.45, blue: 0.77, alpha: 1)
        case .video: NSColor(srgbRed: 0.30, green: 0.57, blue: 0.85, alpha: 1)
        case .audio: NSColor(srgbRed: 0.76, green: 0.46, blue: 0.66, alpha: 1)
        case .archive: NSColor(srgbRed: 0.79, green: 0.57, blue: 0.30, alpha: 1)
        case .code: NSColor(srgbRed: 0.36, green: 0.64, blue: 0.52, alpha: 1)
        case .document: NSColor(srgbRed: 0.63, green: 0.65, blue: 0.41, alpha: 1)
        case .other: NSColor(srgbRed: 0.41, green: 0.49, blue: 0.59, alpha: 1)
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}
let tagColors: [NSColor] = [.clear, .systemRed, .systemYellow, .systemGreen, .systemBlue]

struct TreemapView: NSViewRepresentable {
    @ObservedObject var store: ScanStore
    func makeNSView(context: Context) -> MapCanvas { MapCanvas(store: store) }
    func updateNSView(_ nsView: MapCanvas, context: Context) { nsView.store = store; nsView.refreshGeometry(); nsView.needsDisplay = true }
}

@MainActor
final class MapCanvas: NSView {
    var store: ScanStore
    private var items: [MapItem] = []
    private var transition: MapTransition?
    private var animationTimer: Timer?
    private var acceptsHits = false
    private var geometryPending = false
    private var captureIntents = 0
    private let windowLifecycle = MapWindowLifecycle()
    private var closing = false
    private(set) var deferredGeometryCount = 0
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var isVisuallyActive: Bool {
        guard !closing, let window else { return false }
        return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }
    private func stopVisualWork() {
        geometryGeneration = UUID(); geometryKey = ""; geometryPending = false; acceptsHits = false
        geometryWorker.cancel(); animationTimer?.invalidate(); animationTimer = nil; transition = nil
        items.removeAll(); tooltipRegistry.invalidate(); accessibilityCache.clear(); setAccessibilityChildren([])
        textCache.clear(); geometrySession.reset()
    }
    private func visibilityChanged(closing: Bool = false) {
        if closing {
            self.closing = true; geometryWorker.shutdown(); store.shutdown()
            stopVisualWork(); windowLifecycle.unbind()
        } else if isVisuallyActive {
            refreshGeometry(); needsDisplay = true
        } else if captureIntents == 0 { stopVisualWork() }
    }
    enum CaptureError: Error { case pending, detached }
    func prepareCapture() async throws {
        guard window != nil, !closing else { throw CaptureError.detached }
        captureIntents += 1
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while true {
                guard window != nil, !closing else { throw CaptureError.detached }
                if !store.projectionPending { refreshGeometry() }
                if !store.projectionPending && !geometryPending { break }
                if ProcessInfo.processInfo.systemUptime >= deadline { throw CaptureError.pending }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch { finishCapture(); throw error }
    }
    func finishCapture() {
        captureIntents = max(0, captureIntents - 1)
        if captureIntents == 0 && !isVisuallyActive { stopVisualWork() }
    }
    var presentationStatistics: [String: Int] {
        let geometry = geometrySession.statistics()
        return ["items": items.count, "timer_active": animationTimer == nil ? 0 : 1, "transition_active": transition == nil ? 0 : 1,
            "canvas_width": Int(bounds.width), "canvas_height": Int(bounds.height),
            "geometry_pending": geometryPending ? 1 : 0, "geometry_deferred": deferredGeometryCount,
            "text_entries": textCache.retainedCount, "text_estimated_utf8_bytes": textCache.estimatedUTF8Bytes,
            "text_formats": textCache.formattingCount, "text_measurements": textCache.measurementCount,
            "tooltip_regions": tooltipRegistry.registeredCount, "tooltip_rebuilds": tooltipRegistry.rebuildCount,
            "ax_elements": accessibilityCache.retainedCount, "ax_created": accessibilityCache.createdCount,
            "sort_slots": geometry.retainedSortItems, "rect_tiles": geometry.retainedTiles, "sorts": geometry.sorts,
            "sort_hits": geometry.sortHits, "rect_hits": geometry.rectHits, "window_observers": windowLifecycle.observerCount]
    }
    static func find(in root: NSView) -> MapCanvas? {
        var pending = [root]; var visited = 0
        while let view = pending.popLast(), visited < 4096 {
            visited += 1
            if let canvas = view as? MapCanvas { return canvas }
            pending.append(contentsOf: view.subviews)
        }
        return nil
    }
    private let tooltipRegistry = MapTooltipRegistry()
    private let textCache = MapTextCache()
    private let geometrySession = GeometrySession()
    private lazy var accessibilityCache = MapAccessibilityCache { [weak self] path in
        Task { @MainActor in self?.activateAccessibility(path) }
    }
    private func activateAccessibility(_ path: String) {
        guard acceptsHits, let id = accessibilityCache.targetID(for: path, isCurrent: { [self] id, path in store.node(id)?.path == path }) else { return }
        store.selected = id
    }
    private struct PaletteKey: Hashable {
        let category: FileCategory
        let tag: Int
        let level: Int
        let byType: Bool
    }
    private var paletteCache: [PaletteKey: (NSColor, NSColor)] = [:]
    private func colors(for item: MapItem) -> (NSColor, NSColor) {
        let key = PaletteKey(category: item.category, tag: item.tag, level: item.tile.level, byType: store.colorByType)
        if let cached = paletteCache[key] { return cached }
        var base = store.colorByType ? item.category.nsColor : FileCategory.folder.nsColor
        if item.tag > 0 && item.tag < tagColors.count { base = tagColors[item.tag] }
        let factor: CGFloat = item.node.isDirectory ? max(0.16, 0.29 - CGFloat(item.tile.level) * 0.025) : 0.46
        let fill = base.blended(withFraction: 1 - factor, of: NSColor(srgbRed: 0.07, green: 0.09, blue: 0.115, alpha: 1)) ?? base
        let result = (fill, base.withAlphaComponent(item.node.isDirectory ? 0.45 : 0.70))
        paletteCache[key] = result; return result
    }
    private func presentation(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [MapItem] {
        transition?.items(at: time) ?? items
    }
    func install(_ raw: [MapItem]) {
        let next = textCache.prepare(raw)
        if MapTransition.sameLayout(items, next) {
            items = next; acceptsHits = true; needsDisplay = true; return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let previous = presentation(at: now)
        animationTimer?.invalidate(); animationTimer = nil
        items = next; acceptsHits = true
        if previous.isEmpty || reduceMotion() || !isVisuallyActive {
            transition = nil; needsDisplay = true; return
        }
        transition = MapTransition(from: previous, to: next, at: now)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.animationTick() }
        }
        animationTimer = timer; RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }
    private func animationTick() {
        if !isVisuallyActive && captureIntents == 0 { stopVisualWork(); return }
        if transition?.isFinished(at: ProcessInfo.processInfo.systemUptime) != false {
            transition = nil; animationTimer?.invalidate(); animationTimer = nil
        }
        needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowLifecycle.bind(window) { [weak self] closing in self?.visibilityChanged(closing: closing) }
        if window == nil {
            stopVisualWork()
        } else {
            visibilityChanged()
        }
    }
    private let geometryWorker = LatestWorker<[TreemapTile]>(name: "treemap.geometry")
    private var geometryKey = ""
    private var geometryGeneration = UUID()
    private var lastSize = CGSize.zero
    override func layout() {
        super.layout()
        if lastSize != bounds.size { lastSize = bounds.size; refreshGeometry() }
    }
    func refreshGeometry() {
        guard isVisuallyActive || captureIntents > 0 else {
            deferredGeometryCount += 1; WorkerTelemetry.shared.record("geometry.deferred"); return
        }
        let key = "\(store.projectionRevision)-\(store.focus)-\(store.depth)-\(store.selected ?? -1)-\(bounds.width)-\(bounds.height)"
        guard key != geometryKey, let snapshot = store.snapshot else { return }
        geometryKey = key; let token = UUID(); geometryGeneration = token
        geometryPending = true
        let weights = store.weights; let root = store.focus; let depth = store.depth; let selected = store.selected; let bounds = bounds; let revision = store.projectionRevision
        let source = store.geometrySource ?? GeometrySource(snapshot: snapshot, weights: weights)
        let session = geometrySession
        // Invalidate hit targets immediately; stale geometry must never address a new node table.
        acceptsHits = false; tooltipRegistry.invalidate(); accessibilityCache.invalidateTargets(); setAccessibilityChildren([])
        geometryWorker.submit(operation: { control in
            session.tiles(source: source, root: root, depth: depth, selected: selected, in: bounds, control: control)
        }, completion: { [weak self] tiles in
            Task { @MainActor in
                guard let self, self.geometryGeneration == token, self.store.projectionRevision == revision else { return }
                self.geometryPending = false
                let next = tiles.map { tile -> MapItem in
                    let node = snapshot.nodes[tile.id]
                    return MapItem(tile: tile, node: node, parentPath: node.parent.map { snapshot.nodes[$0].path }, sizeText: "", sizeWidth: 0,
                        tag: self.store.effectiveTag(tile.id), category: FileCategory.of(node), displayBytes: weights[tile.id])
                }
                self.install(next)
            }
        })
    }
    private var clickAnchor: (id: Int, path: String)?
    private var hovered: Int?
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(store: ScanStore) {
        self.store = store; super.init(frame: .zero)
        CanvasLifetime.shared.add()
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("디스크 사용량 트리맵")
        setAccessibilityHelp("파일 크기에 비례한 영역입니다. 클릭하면 내부 상세가 열리고, 더블 클릭하면 폴더를 화면 전체로 확대합니다. 방향키와 Return으로 탐색할 수 있습니다.")
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { CanvasLifetime.shared.remove() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func draw(_ dirtyRect: NSRect) {
        let frameStarted = DispatchTime.now().uptimeNanoseconds
        defer { WorkerTelemetry.shared.observe("paint.frame", nanoseconds: DispatchTime.now().uptimeNanoseconds &- frameStarted) }
        NSColor(srgbRed: 0.055, green: 0.075, blue: 0.095, alpha: 1).setFill(); bounds.fill()
        guard let snapshot = store.snapshot, snapshot.nodes.indices.contains(store.focus), store.weights.count == snapshot.nodes.count else {
            tooltipRegistry.invalidate(); accessibilityCache.clear(); textCache.clear(); setAccessibilityChildren([]); return
        }
        func text(_ string: String, rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
            guard rect.width > 12, rect.height > textCache.pointSize else { return }
            (string as NSString).draw(in: rect, withAttributes: attributes)
        }
        let visible = presentation()
        let boxes = WorkerTelemetry.shared.measure("paint.rect_index") { Dictionary(uniqueKeysWithValues: visible.map { ($0.node.path, $0.tile.rect) }) }
        func drawItem(_ item: MapItem) {
            let tile = item.tile; let box = tile.rect
            guard box.width > 1, box.height > 1 else { return }
            let node = item.node
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(item.opacity)
            if let parentPath = item.parentPath, let parent = boxes[parentPath] {
                let inner = CGRect(x: parent.minX + 3, y: parent.minY + 25,
                    width: max(0, parent.width - 6), height: max(0, parent.height - 28))
                NSBezierPath(rect: inner).addClip()
            }
            defer { NSGraphicsContext.restoreGraphicsState() }
            let (fill, stroke) = colors(for: item)
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            fill.setFill(); path.fill()
            stroke.setStroke(); path.lineWidth = 1; path.stroke()
            let canNest = tile.expanded
            if box.width > 34 && box.height > 22 {
                let title = item.titleText ?? (node.isDirectory ? "▸ " : node.isSymbolicLink ? "↗ " : "") + node.name
                if canNest {
                    // Keep the current calculated size visible even when a folder is expanded.
                    let width = min(item.sizeWidth + 1, box.width - 16)
                    text(title, rect: CGRect(x: box.minX + 8, y: box.minY + 6,
                        width: max(0, box.width - width - 28), height: 18), attributes: textCache.folderAttributes)
                    text(item.sizeText, rect: CGRect(x: box.maxX - width - 8, y: box.minY + 6,
                        width: width, height: 18), attributes: textCache.headerSizeAttributes)
                } else {
                    text(title, rect: CGRect(x: box.minX + 8, y: box.minY + 6, width: box.width - 16, height: 18), attributes: node.isDirectory ? textCache.folderAttributes : textCache.titleAttributes)
                }
                if !canNest && box.height > 49 {
                    text(item.sizeText, rect: CGRect(x: box.minX + 8, y: box.minY + 26, width: box.width - 16, height: 19), attributes: textCache.leafSizeAttributes)
                }
            }
        }
        WorkerTelemetry.shared.measure("paint.tiles") { for item in visible { drawItem(item) } }
        WorkerTelemetry.shared.measure("paint.tooltip") {
            tooltipRegistry.update(visible, view: self, acceptsHits: acceptsHits,
                isCurrent: { [self] id, path in store.node(id)?.path == path })
        }
        // Current path/ID mapping is bounded to the same 500 exposed children.
        let accessibilityNodes = WorkerTelemetry.shared.measure("paint.ax") { accessibilityCache.update(visible, focus: store.focus, acceptsHits: acceptsHits, parent: self,
            isCurrent: { [self] id, path in store.node(id)?.path == path },
            screenFrame: { [self] rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }) }
        setAccessibilityChildren(accessibilityNodes)
        for id in [hovered, store.selected].compactMap({ $0 }) {
            if let tile = visible.first(where: { $0.interactive && $0.tile.id == id })?.tile {
                let path = NSBezierPath(roundedRect: tile.rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
                NSColor.white.withAlphaComponent(id == store.selected ? 1 : 0.45).setStroke()
                path.lineWidth = id == store.selected ? 2 : 1; path.stroke()
            }
        }
    }
    private func hit(_ event: NSEvent) -> Int? {
        guard acceptsHits else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return presentation().last(where: {
            $0.interactive && $0.opacity > 0.5 && $0.tile.rect.contains(point) && store.node($0.tile.id)?.path == $0.node.path
        })?.tile.id
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            // Native dbl-click sets the 0x761 guard, preventing its second mouse-down from
            // selecting a newly exposed child. Keep the first click's node across async layout.
            let anchored = clickAnchor.flatMap { store.node($0.id)?.path == $0.path ? $0.id : nil }
            if let id = anchored ?? hit(event) { store.zoomTarget(id) }
            clickAnchor = nil; return
        }
        guard let id = hit(event), let node = store.node(id) else { store.selected = nil; clickAnchor = nil; return }
        clickAnchor = (id, node.path); store.selected = id
    }
    override func mouseMoved(with event: NSEvent) { let id = hit(event); if id != hovered { hovered = id; needsDisplay = true } }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let node = tooltipRegistry.node(for: tag, userData: data, resolve: { [self] in store.node($0) }) else { return "" }
        return "\(node.path)\n디스크: \(formattedBytes(node.allocatedBytes)) · 파일: \(formattedBytes(node.logicalBytes))\n수정: \(node.modified.formatted())\(node.issue.map { "\n⚠ \($0)" } ?? "")"
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124, 125, 126:
            let ids = store.visibleChildren
            guard !ids.isEmpty else { return }
            let current = store.selected.flatMap { ids.firstIndex(of: $0) } ?? -1
            let direction = event.keyCode == 123 || event.keyCode == 126 ? -1 : 1
            store.selected = ids[(max(0, current + direction) + ids.count) % ids.count]
        case 49: if let id = store.selected { store.preview(id) }
        case 36: if let id = store.selected { store.zoomTarget(id) }
        case 51:
            if event.modifierFlags.contains(.command), let id = store.selected { store.trash(id) }
            else if event.modifierFlags.contains(.shift) { store.forward() } else { store.back() }
        case 18, 19, 20, 21: // 1...4: reference FormKeyDown 0x42f0a0
            if let id = hovered ?? store.selected { store.tag(id, color: [18: 1, 19: 2, 20: 3, 21: 4][event.keyCode]!) }
        case 29: store.clearTagsInFocus()
        case 53: store.selected = nil
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let id = hit(event), let node = store.node(id) else { return nil }
        store.selected = id
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, enabled: Bool = true, tag: Int = 0) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self
            entry.isEnabled = enabled; entry.tag = tag; menu.addItem(entry)
        }
        menu.autoenablesItems = false
        item(node.isDirectory ? "폴더로 확대" : "기본 앱으로 열기", #selector(openSelected), enabled: node.isDirectory || !store.offline)
        item("Finder에서 보기", #selector(revealSelected), enabled: !store.offline)
        item("빠른 보기", #selector(previewSelected), enabled: !store.offline)
        item("경로 복사", #selector(copySelected)); menu.addItem(.separator())
        for (index, title) in ["태그 해제", "🔴 빨강", "🟡 노랑", "🟢 초록", "🔵 파랑"].enumerated() {
            item(title, #selector(tagSelected(_:)), tag: index)
        }
        menu.addItem(.separator())
        item("휴지통으로 이동…", #selector(trashSelected), enabled: !store.offline && !store.isScanning && id != 0)
        return menu
    }
    @objc private func openSelected() { if let id = store.selected { store.open(id) } }
    @objc private func revealSelected() { if let id = store.selected { store.reveal(id) } }
    @objc private func previewSelected() { if let id = store.selected { store.preview(id) } }
    @objc private func copySelected() { if let id = store.selected { store.copyPath(id) } }
    @objc private func trashSelected() { if let id = store.selected { store.trash(id) } }
    @objc private func tagSelected(_ sender: NSMenuItem) { if let id = store.selected { store.tag(id, color: sender.tag) } }
}

