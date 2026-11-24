import AppKit
import XCTest
import SpaceSnifferCore
@testable import MacSpaceSniffer

@MainActor
final class MapTooltipTests: XCTestCase {
    private func item(_ id: Int, path: String? = nil, rect: CGRect = CGRect(x: 1, y: 2, width: 80, height: 60), opacity: Double = 1, interactive: Bool = true) -> MapItem {
        MapItem(tile: TreemapTile(id: id, rect: rect, expanded: false, level: 0),
            node: DiskNode(id: id, parent: 0, path: path ?? "/root/\(id)", name: "node-\(id)"), parentPath: "/root",
            sizeText: "1 KB", sizeWidth: 20, tag: 0, category: .other, opacity: opacity, interactive: interactive)
    }
    private func update(_ registry: MapTooltipRegistry, _ items: [MapItem], view: NSView) {
        registry.update(items, view: view, acceptsHits: true, isCurrent: { _, _ in true })
    }
    func testStationaryRedrawSkipsRegistrationAndContentResolvesLive() throws {
        let registry = MapTooltipRegistry(); let view = NSView()
        let items = (1...100).map { item($0) }
        for _ in 0..<60 { update(registry, items, view: view) }
        XCTAssertEqual(registry.rebuildCount, 1); XCTAssertEqual(registry.addCount, 100)
        let registration = try XCTUnwrap(registry.registrations.first)
        var current = items[0].node; current.logicalBytes = 500; current.issue = "new issue"
        let resolved = registry.node(for: registration.tag, userData: UnsafeMutableRawPointer(bitPattern: registration.token), resolve: { _ in current })
        XCTAssertEqual(resolved?.logicalBytes, 500); XCTAssertEqual(resolved?.issue, "new issue")
        registry.invalidate()
    }
    func testRebuildRejectsDelayedTokenAndReusedNodeID() throws {
        let registry = MapTooltipRegistry(); let view = NSView()
        update(registry, [item(1, path: "/root/old")], view: view)
        let old = try XCTUnwrap(registry.registrations.first)
        update(registry, [item(1, path: "/root/new")], view: view)
        let new = try XCTUnwrap(registry.registrations.first)
        XCTAssertNotEqual(old.token, new.token)
        XCTAssertNil(registry.node(for: new.tag, userData: UnsafeMutableRawPointer(bitPattern: old.token), resolve: { _ in self.item(1, path: "/root/new").node }))
        XCTAssertNil(registry.node(for: new.tag, userData: UnsafeMutableRawPointer(bitPattern: new.token), resolve: { _ in self.item(1, path: "/root/mismatch").node }))
        XCTAssertEqual(registry.node(for: new.tag, userData: UnsafeMutableRawPointer(bitPattern: new.token), resolve: { _ in self.item(1, path: "/root/new").node })?.path, "/root/new")
        registry.invalidate()
        XCTAssertNil(registry.node(for: new.tag, userData: UnsafeMutableRawPointer(bitPattern: new.token), resolve: { _ in self.item(1, path: "/root/new").node }))
    }
    func testEligibilityAndOrderMatchOriginalAndPendingGeometryDisablesTargets() {
        let registry = MapTooltipRegistry(); let view = NSView()
        let items = [item(1), item(2, opacity: 0.5), item(3, interactive: false),
            item(4, rect: CGRect(x: 2, y: 3, width: 15, height: 40)), item(5, rect: CGRect(x: 5, y: 6, width: 30, height: 20))]
        let original = items.filter { $0.interactive && $0.opacity > 0.5 && $0.tile.rect.width > 15 && $0.tile.rect.height > 15 }
        update(registry, items, view: view)
        XCTAssertEqual(registry.registeredRects, original.map { $0.tile.rect })
        registry.update(items, view: view, acceptsHits: false, isCurrent: { _, _ in true })
        XCTAssertEqual(registry.registeredCount, 0)
        registry.update(items, view: view, acceptsHits: true, isCurrent: { _, _ in false })
        XCTAssertEqual(registry.registeredCount, 0)
        registry.invalidate()
    }
    func testTransitionFramesAndInterruptedTransitionUseCurrentPresentationRects() {
        let registry = MapTooltipRegistry(); let view = NSView()
        let first = [item(1, rect: CGRect(x: 0, y: 0, width: 100, height: 100))]
        let last = [item(1, rect: CGRect(x: 100, y: 40, width: 150, height: 200)), item(2)]
        let transition = MapTransition(from: first, to: last, at: 10)
        for time in [10.0, 10.15, 10.35, 10.5] {
            let visible = transition.items(at: time)
            update(registry, visible, view: view)
            XCTAssertEqual(registry.registeredRects, visible.filter { $0.interactive && $0.opacity > 0.5 && $0.tile.rect.width > 15 && $0.tile.rect.height > 15 }.map { $0.tile.rect })
        }
        let interrupted = MapTransition(from: transition.items(at: 10.2), to: first, at: 10.2)
        let visible = interrupted.items(at: 10.35)
        update(registry, visible, view: view)
        XCTAssertEqual(registry.registeredRects, visible.filter { $0.interactive && $0.opacity > 0.5 && $0.tile.rect.width > 15 && $0.tile.rect.height > 15 }.map { $0.tile.rect })
        registry.invalidate()
    }
    func testInvalidationReleasesViewAndOnlyCurrentTargetsRemain() {
        let registry = MapTooltipRegistry(); weak var weakView: NSView?
        autoreleasepool {
            let view = NSView(); weakView = view
            update(registry, (1...100).map { item($0) }, view: view)
            update(registry, [item(2)], view: view)
            XCTAssertEqual(registry.registeredCount, 1)
            registry.invalidate(); registry.invalidate(); XCTAssertEqual(registry.registeredCount, 0)
            XCTAssertTrue(registry.registeredRects.isEmpty)
        }
        XCTAssertNil(weakView)
    }
}
