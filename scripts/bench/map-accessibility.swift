import AppKit
import SpaceSnifferCore

// Preserved pre-cache draw path, with injected parent/frame and a no-op selection callback.
// Original source is retained in validation/accessibility-cache-2026-11-09/TreemapView-before.swift.
@MainActor private final class LegacyAXElement: NSAccessibilityElement {
    nonisolated let action: @Sendable () -> Void
    init(action: @escaping @Sendable () -> Void) { self.action = action; super.init() }
    nonisolated override func accessibilityPerformPress() -> Bool { action(); return true }
}
@MainActor private func legacy(_ visible: [MapItem], parent: NSView) -> [NSAccessibilityElement] {
    visible.filter { $0.interactive && $0.node.parent == 0 && $0.opacity > 0.5 && $0.tile.id == $0.node.id }.prefix(500).map { item in
        let tile = item.tile
        let element = LegacyAXElement { _ = tile.id }
        element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true); element.setAccessibilityParent(parent)
        element.setAccessibilityLabel("\(item.node.name), \(item.sizeText)"); element.setAccessibilityFrame(item.tile.rect)
        return element
    }
}
@main enum AccessibilityProbe {
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]; let count = Int(CommandLine.arguments[2])!; let frames = Int(CommandLine.arguments[3])!
        let fixture = (1...count).map { id in
            MapItem(tile: TreemapTile(id: id, rect: CGRect(x: id, y: 2, width: 30, height: 40), expanded: false, level: 0),
                node: DiskNode(id: id, parent: 0, path: "/root/\(id)", name: "node-\(id)"), parentPath: "/root", sizeText: "1 KB", sizeWidth: 20, tag: 0, category: .other)
        }
        let parent = NSView(); let cache = MapAccessibilityCache { _ in }
        var creates = 0; var visits = 0; var hash: UInt64 = 14695981039346656037
        let start = ContinuousClock.now
        for _ in 0..<frames {
            autoreleasepool {
                let children: [NSAccessibilityElement]
                if mode == "legacy" { children = legacy(fixture, parent: parent); creates += children.count; visits += fixture.count }
                else {
                    children = cache.update(fixture, focus: 0, acceptsHits: true, parent: parent,
                        isCurrent: { id, path in fixture[id-1].node.path == path }, screenFrame: { $0 })
                    visits += cache.visitedCount
                }
                precondition(children.count == min(count, 500))
                parent.setAccessibilityChildren(children)
                for element in [children.first!, children.last!] {
                    for byte in element.accessibilityLabel()!.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
                    hash = (hash ^ UInt64(element.accessibilityFrame().minX)) &* 1099511628211
                }
            }
        }
        let duration = start.duration(to: .now).components
        if mode != "legacy" { creates = cache.createdCount }
        let retained = cache.retainedCount
        parent.setAccessibilityChildren([]); cache.clear()
        let row: [String: Any] = ["mode":mode,"items":count,"frames":frames,"seconds":Double(duration.seconds)+Double(duration.attoseconds)/1e18,
            "created_elements":creates,"visited_items":visits,"retained_elements_before_clear":retained,"retained_elements_after_clear":cache.retainedCount,"checksum":String(hash)]
        print(String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
    }
}
