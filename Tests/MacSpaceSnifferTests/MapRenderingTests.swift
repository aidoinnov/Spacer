import AppKit
import Darwin
import XCTest
import SpaceSnifferCore
import SnifferTestSupport
@testable import MacSpaceSniffer

@MainActor
final class MapRenderingTests: XCTestCase {
    private func fixture() -> (ScanSnapshot, [Int64], [MapItem]) {
        let nodes = [DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, children: [1,3,4]),
            DiskNode(id: 1, parent: 0, path: "/r/folder", name: "folder", isDirectory: true, logicalBytes: 1537, children: [2]),
            DiskNode(id: 2, parent: 1, path: "/r/folder/cafe\u{301}.bin", name: "cafe\u{301}.bin", logicalBytes: 1537),
            DiskNode(id: 3, parent: 0, path: "/r/link", name: "link", isSymbolicLink: true),
            DiskNode(id: 4, parent: 0, path: "/r/long.bin", name: String(repeating: "long 한글 ", count: 16), logicalBytes: 9_007_199_254_740_993)]
        let snapshot = ScanSnapshot(rootPath: "/r", nodes: nodes)
        let weights: [Int64] = [9_007_199_254_742_530,1537,1537,0,9_007_199_254_740_993]
        let rects = [CGRect.zero, CGRect(x: 10, y: 10, width: 450, height: 220), CGRect(x: 16, y: 40, width: 430, height: 180), CGRect(x: 480, y: 10, width: 300, height: 220), CGRect(x: 10, y: 250, width: 770, height: 330)]
        let font = NSFont.systemFont(ofSize: 11)
        let items = (1..<nodes.count).map { id in
            let size = formattedBytes(weights[id])
            return MapItem(tile: TreemapTile(id: id, rect: rects[id], expanded: id == 1, level: id == 2 ? 2 : 1), node: nodes[id], parentPath: nodes[id].parent == 1 ? "/r/folder" : "/r",
                sizeText: size, sizeWidth: (size as NSString).size(withAttributes: [.font: font]).width, tag: 0, category: FileCategory.of(nodes[id]), displayBytes: weights[id])
        }
        return (snapshot, weights, items)
    }
    private func pixels(_ view: NSView) -> Data {
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        view.draw(view.bounds); NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: image.bitmapData!, count: image.bytesPerRow * image.pixelsHigh)
    }
    @inline(never) private func sampledPixels(_ view: NSView) -> Data {
        autoreleasepool { pixels(view) }
    }
    func testRendererPixelsEqualPreservedReferenceAndTextReuseInvalidatesExactly() {
        autoreleasepool {
            let (snapshot, weights, items) = fixture(); let store = ScanStore(); store.snapshot = snapshot; store.weights = weights
            let current = MapCanvas(store: store); let old = LegacyMapCanvas(store: store)
            current.frame = CGRect(x: 0, y: 0, width: 800, height: 600); old.frame = current.frame
            current.install(items); old.install(items)
            XCTAssertEqual(pixels(current), pixels(old))
            let count = current.presentationStatistics["text_measurements"]
            current.install(items); XCTAssertEqual(current.presentationStatistics["text_measurements"], count)
            store.selected = 1; XCTAssertEqual(pixels(current), pixels(old))
            current.viewDidMoveToWindow(); old.viewDidMoveToWindow(); store.shutdown()
            XCTAssertEqual(current.presentationStatistics["text_entries"], 0); XCTAssertEqual(current.presentationStatistics["tooltip_regions"], 0); XCTAssertEqual(current.presentationStatistics["ax_elements"], 0)
        }
    }
    func testTextCacheBoundsUTF8FontAndFrozenPresentation() {
        let cache = MapTextCache(entryLimit: 2, byteLimit: 3000)
        let (_, _, items) = fixture(); let frozen = cache.prepare(items)
        XCTAssertLessThanOrEqual(cache.retainedCount, 2); XCTAssertLessThanOrEqual(cache.estimatedUTF8Bytes, 3000)
        let first = cache.measurementCount
        _ = cache.prepare(Array(items.prefix(2))); let second = cache.measurementCount
        XCTAssertEqual(first, second)
        var changed = items[0]; changed.displayBytes = 500_000
        let new = cache.prepare([changed])[0]; XCTAssertNotEqual(new.sizeText, frozen[0].sizeText)
        XCTAssertEqual(frozen[0].sizeText, formattedBytes(1537))
        cache.setPointSize(20); let larger = cache.prepare([changed])[0]
        XCTAssertGreaterThan(larger.sizeWidth, new.sizeWidth)
        func renamed(_ name: String) -> MapItem {
            var node = changed.node; node.name = name
            return MapItem(tile: changed.tile, node: node, parentPath: changed.parentPath, sizeText: changed.sizeText,
                sizeWidth: changed.sizeWidth, tag: changed.tag, category: changed.category, displayBytes: changed.displayBytes)
        }
        _ = cache.prepare([renamed("café")]); let renamed = renamed("cafe\u{301}")
        XCTAssertEqual(Array(cache.prepare([renamed])[0].titleText!.utf8), Array("▸ cafe\u{301}".utf8))
        cache.clear(); XCTAssertEqual(cache.retainedCount, 0)
    }
    func testDetachedCanvasDefersGeometryAndReleaseDropsAllOwnedState() {
        weak var weakCanvas: MapCanvas?; weak var weakStore: ScanStore?
        autoreleasepool {
            let store = ScanStore(); let canvas = MapCanvas(store: store)
            weakCanvas = canvas; weakStore = store
            canvas.refreshGeometry(); XCTAssertGreaterThan(canvas.deferredGeometryCount, 0)
            canvas.viewDidMoveToWindow(); store.shutdown()
        }
        XCTAssertNil(weakCanvas); XCTAssertNil(weakStore)
    }
    func testShutdownDropsLoadedInputAndPreservesExistingQueryReader() async throws {
        let input = OptimizationFixture.metadata(files: 2000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-close-" + UUID().uuidString + ".sns")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ArtifactWorker.shared.save(input, to: url)
        let store = ScanStore(); try await store.loadSnapshotAwaiting(url)
        for _ in 0..<500 where store.projectionPending { try await Task.sleep(for: .milliseconds(5)) }
        let reader = try XCTUnwrap(store.automationContext); let frozen = try SNSSnapshot.encode(reader.snapshot)
        weak var geometry = store.geometrySource
        XCTAssertNotNil(store.projectionSource); store.shutdown(); store.shutdown()
        XCTAssertNil(store.snapshot); XCTAssertNil(store.projectionSource); XCTAssertNil(store.geometrySource)
        XCTAssertTrue(store.weights.isEmpty); XCTAssertFalse(store.projectionPending)
        XCTAssertNil(geometry)
        XCTAssertEqual(try SNSSnapshot.encode(reader.snapshot), frozen)
    }
    func testTransitionInterruptionAndReduceMotionKeepLatestHitTargets() {
        let (snapshot, weights, items) = fixture(); let store = ScanStore(); store.snapshot = snapshot; store.weights = weights
        let canvas = MapCanvas(store: store); canvas.reduceMotion = { true }; canvas.install(items)
        canvas.install(Array(items.reversed()))
        XCTAssertEqual(canvas.presentationStatistics["timer_active"], 0)
        XCTAssertEqual(canvas.presentationStatistics["transition_active"], 0)
        let first = MapTransition(from: items, to: [items[2]], at: 1)
        let interrupted = MapTransition(from: first.items(at: 1.2), to: items, at: 1.2)
        let final = interrupted.items(at: 1.7)
        XCTAssertEqual(final.filter(\.interactive).map { $0.node.path }, items.map { $0.node.path })
        XCTAssertEqual(final.filter(\.interactive).map { $0.tile.rect }, items.map { $0.tile.rect })
        canvas.viewDidMoveToWindow(); store.shutdown()
    }
    func testRenderProbe() throws {
        guard let output = ProcessInfo.processInfo.environment["SNIFFER_RENDER_REPORT"] else { throw XCTSkip("Explicit release performance run only") }
        var (snapshot, weights, items) = fixture()
        let dense = ProcessInfo.processInfo.environment["SNIFFER_RENDER_DENSE"] == "1"
        if dense {
            snapshot = ScanSnapshot(rootPath: "/render", nodes: [DiskNode(id: 0, parent: nil, path: "/render", name: "render", isDirectory: true)])
            weights = [0]; items = []
            for id in 1...200 {
                let bytes = Int64(id * 1025); let node = DiskNode(id: id, parent: 0, path: "/render/\(id)", name: "한글 café file-\(id).bin", logicalBytes: bytes)
                snapshot.nodes.append(node); snapshot.nodes[0].children.append(id); weights.append(bytes); weights[0] += bytes
                let size = formattedBytes(bytes)
                items.append(MapItem(tile: TreemapTile(id: id, rect: CGRect(x: ((id-1)%20)*40, y: ((id-1)/20)*60, width: 40, height: 60), expanded: false, level: 1), node: node,
                    parentPath: "/render", sizeText: size, sizeWidth: (size as NSString).size(withAttributes: [.font:NSFont.systemFont(ofSize: 11)]).width,
                    tag: 0, category: .other, displayBytes: bytes))
            }
        }
        let store = ScanStore(); store.snapshot = snapshot; store.weights = weights
        let current = MapCanvas(store: store); let old = LegacyMapCanvas(store: store)
        current.frame = CGRect(x: 0, y: 0, width: 800, height: 600); old.frame = current.frame
        current.install(items); old.install(items)
        XCTAssertEqual(pixels(current), pixels(old))
        for _ in 0..<10 { _ = pixels(old); _ = pixels(current) }
        var rows: [[String: Any]] = []
        let profiling = ProcessInfo.processInfo.environment["SNIFFER_RENDER_PROFILE_WAIT"] == "1"
        let pairs = profiling ? 1 : 5; let frames = profiling ? 20 : 250
        for pair in 0..<pairs {
            for mode in pair % 2 == 0 ? ["legacy","current"] : ["current","legacy"] {
                var seconds: [Double] = []
                for index in 0..<frames {
                    store.selected = index % 2 == 0 ? 1 : 4
                    let start = DispatchTime.now().uptimeNanoseconds
                    let data = sampledPixels(mode == "legacy" ? old : current)
                    XCTAssertEqual(data.count, 800*600*4)
                    seconds.append(Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9)
                }
                rows.append(["pair":pair,"mode":mode,"seconds":seconds])
            }
        }
        try JSONSerialization.data(withJSONObject: ["scope":"offscreen full AppKit renderer, selected outline toggles; bitmap allocation/copy included equally; not screen compositor FPS; instrumented run uses fewer frames", "items":items.count, "pairs":pairs, "frames_per_pair":frames, "rows": rows], options: [.sortedKeys]).write(to: URL(fileURLWithPath: output))
        current.viewDidMoveToWindow(); old.viewDidMoveToWindow(); store.shutdown()
        if ProcessInfo.processInfo.environment["SNIFFER_RENDER_PROFILE_WAIT"] == "1" {
            print("SNIFFER_RENDER_PROFILE_READY"); fflush(stdout)
            _ = FileHandle.standardInput.readData(ofLength: 1)
        }
    }
}
