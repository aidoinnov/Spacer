import AppKit
import SpaceSnifferCore

/// Current presentation registrations only. Tooltip content is resolved live, never cached.
@MainActor
final class MapTooltipRegistry {
    private struct Area: Equatable { let id: Int; let path: String; let rect: CGRect }
    private var areas: [Area] = []
    private var tags: [NSView.ToolTipTag] = []
    private weak var view: NSView?
    private var firstToken = 1
    private var nextToken = 1
    private(set) var rebuildCount = 0
    private(set) var addCount = 0
    var registeredCount: Int { tags.count }
    var registeredRects: [CGRect] { areas.map(\.rect) }
    var registrations: [(token: Int, tag: NSView.ToolTipTag)] {
        tags.enumerated().map { (firstToken + $0.offset, $0.element) }
    }
    func invalidate() {
        view?.removeAllToolTips(); view = nil; areas.removeAll(); tags.removeAll()
    }
    func update(_ items: [MapItem], view: NSView, acceptsHits: Bool, isCurrent: (Int, String) -> Bool) {
        guard acceptsHits else { invalidate(); return }
        var next: [Area] = []
        for item in items where item.interactive && item.opacity > 0.5 && item.tile.rect.width > 15 && item.tile.rect.height > 15 {
            guard isCurrent(item.tile.id, item.node.path) else { continue }
            next.append(Area(id: item.tile.id, path: item.node.path, rect: item.tile.rect))
        }
        guard self.view !== view || areas != next else { return }
        invalidate(); self.view = view; areas = next; firstToken = nextToken; rebuildCount += 1
        for area in next {
            // Never reuse userdata tokens: a delayed callback must not address a new ID.
            let token = nextToken; nextToken += 1
            let tag = view.addToolTip(area.rect, owner: view, userData: UnsafeMutableRawPointer(bitPattern: token))
            tags.append(tag); addCount += 1
        }
    }
    func node(for tag: NSView.ToolTipTag, userData: UnsafeMutableRawPointer?, resolve: (Int) -> DiskNode?) -> DiskNode? {
        guard let userData else { return nil }
        let token = Int(bitPattern: userData)
        guard token >= firstToken else { return nil }
        let index = token - firstToken
        guard tags.indices.contains(index), tags[index] == tag,
              let node = resolve(areas[index].id), node.path == areas[index].path else { return nil }
        return node
    }
}
