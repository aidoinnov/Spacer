import AppKit
import XCTest
import SpaceSnifferCore
@testable import MacSpaceSniffer

@MainActor
final class MapAccessibilityTests: XCTestCase {
    private func item(_ id: Int, path: String? = nil, parent: Int = 0, opacity: Double = 1, interactive: Bool = true, sizeText: String = "1 KB", name: String? = nil) -> MapItem {
        MapItem(tile: TreemapTile(id: id, rect: CGRect(x: id, y: 2, width: 30, height: 40), expanded: false, level: 0),
            node: DiskNode(id: id, parent: parent, path: path ?? "/root/\(id)", name: name ?? "node-\(id)"), parentPath: "/root",
            sizeText: sizeText, sizeWidth: 20, tag: 0, category: .other, opacity: opacity, interactive: interactive)
    }
    private func update(_ cache: MapAccessibilityCache, _ items: [MapItem], parent: NSView) -> [NSAccessibilityElement] {
        cache.update(items, focus: 0, acceptsHits: true, parent: parent, isCurrent: { _, _ in true }, screenFrame: { $0 })
    }
    func testBoundedCandidatesMatchLegacyOrderAndStopBeforeTrailingItems() {
        let cache = MapAccessibilityCache { _ in }; let view = NSView()
        var items = [item(1, parent: 8), item(2, opacity: 0.5), item(3, interactive: false)]
        items += (4..<10004).map { item($0) }
        let old = items.filter { $0.interactive && $0.node.parent == 0 && $0.opacity > 0.5 }.prefix(500)
        let children = update(cache, items, parent: view)
        XCTAssertEqual(children.map { $0.accessibilityLabel() }, old.map { "\($0.node.name), \($0.sizeText)" })
        XCTAssertEqual(cache.visitedCount, 503); XCTAssertEqual(cache.retainedCount, 500)
        XCTAssertEqual(cache.createdCount, 500); cache.clear()
    }
    func testIdentitySurvivesIDRelocationAndLabelFrameChanges() {
        let cache = MapAccessibilityCache { _ in }; let view = NSView()
        let first = update(cache, [item(1, path: "/root/stable")], parent: view)[0]
        let changed = item(70, path: "/root/stable", sizeText: "20 GB")
        let second = update(cache, [changed], parent: view)[0]
        XCTAssertTrue(first === second); XCTAssertEqual(cache.createdCount, 1)
        XCTAssertEqual(second.accessibilityLabel(), "node-70, 20 GB")
        XCTAssertEqual(second.accessibilityFrame(), changed.tile.rect)
        XCTAssertEqual(cache.targetID(for: "/root/stable", isCurrent: { id, path in id == 70 && path == "/root/stable" }), 70)
        XCTAssertNil(cache.targetID(for: "/root/stable", isCurrent: { _, _ in false }))
        _ = update(cache, [item(70, path: "/root/stable", name: "café")], parent: view)
        let normalized = update(cache, [item(70, path: "/root/stable", name: "cafe\u{301}")], parent: view)[0]
        XCTAssertTrue(normalized === first)
        XCTAssertEqual(Array(normalized.accessibilityLabel()!.utf8), Array("cafe\u{301}, 1 KB".utf8))
        cache.clear()
    }
    func testOldElementActivationUsesCurrentValidatedPathAndCannotKeepOwnerAlive() async throws {
        var owner: AccessibilityOwner? = AccessibilityOwner(); weak let weakOwner = owner
        let cache = MapAccessibilityCache { [weak owner] path in Task { @MainActor in owner?.pressed(path) } }
        owner?.cache = cache; let view = NSView()
        let retained = update(cache, [item(1, path: "/root/kept")], parent: view)[0]
        _ = update(cache, [item(12, path: "/root/kept")], parent: view)
        owner?.current = [12: "/root/kept"]
        XCTAssertTrue(retained.accessibilityPerformPress()); try await waitForPress(owner, count: 1); XCTAssertEqual(owner?.selected, 12)
        owner?.selected = nil; owner?.current = [12: "/root/replacement"]
        _ = retained.accessibilityPerformPress(); try await waitForPress(owner, count: 2); XCTAssertNil(owner?.selected)
        cache.invalidateTargets(); owner?.current = [12: "/root/kept"]
        _ = retained.accessibilityPerformPress(); try await waitForPress(owner, count: 3); XCTAssertNil(owner?.selected)
        owner = nil; XCTAssertNil(weakOwner)
        _ = retained.accessibilityPerformPress(); cache.clear()
    }
    private func waitForPress(_ owner: AccessibilityOwner?, count: Int) async throws {
        for _ in 0..<100 {
            if owner?.presses == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("AX callback did not execute")
    }
    func testPruningAndClearReleaseElementsAndParentReferences() {
        let cache = MapAccessibilityCache { _ in }; let view = NSView()
        var first: NSAccessibilityElement? = update(cache, [item(1), item(2)], parent: view)[0]
        weak let weakElement = first
        _ = update(cache, [item(2)], parent: view)
        XCTAssertNil(first?.accessibilityParent())
        first = nil; XCTAssertNil(weakElement); XCTAssertEqual(cache.retainedCount, 1)
        cache.clear(); XCTAssertEqual(cache.retainedCount, 0)
        XCTAssertNil(cache.targetID(for: "/root/2", isCurrent: { _, _ in true }))
        let empty = cache.update([item(1)], focus: 0, acceptsHits: false, parent: view, isCurrent: { _, _ in true }, screenFrame: { $0 })
        XCTAssertTrue(empty.isEmpty)
    }
}

@MainActor
private final class AccessibilityOwner {
    var cache: MapAccessibilityCache?
    var current: [Int: String] = [:]
    var selected: Int?
    var presses = 0
    func pressed(_ path: String) {
        presses += 1
        guard let id = cache?.targetID(for: path, isCurrent: { [self] id, path in current[id] == path }) else { return }
        selected = id
    }
}
