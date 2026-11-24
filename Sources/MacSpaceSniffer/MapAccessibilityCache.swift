import AppKit

/// Bounded presentation ownership. It never stores MapItem, DiskNode or a snapshot.
@MainActor
final class MapAccessibilityCache {
    private var elements: [String: MapAccessibilityElement] = [:]
    private var targets: [String: Int] = [:]
    private weak var parent: NSView?
    private let action: @Sendable (String) -> Void
    private(set) var createdCount = 0
    private(set) var visitedCount = 0
    var retainedCount: Int { elements.count }
    init(action: @escaping @Sendable (String) -> Void) { self.action = action }
    func targetID(for path: String, isCurrent: (Int, String) -> Bool) -> Int? {
        guard let id = targets[path], isCurrent(id, path) else { return nil }
        return id
    }
    func invalidateTargets() {
        targets.removeAll()
        for element in elements.values { element.setAccessibilityParent(nil) }
        parent = nil
    }
    func clear() { invalidateTargets(); elements.removeAll() }
    func update(_ items: [MapItem], focus: Int, acceptsHits: Bool, parent: NSView,
                isCurrent: (Int, String) -> Bool, screenFrame: (CGRect) -> CGRect?) -> [NSAccessibilityElement] {
        visitedCount = 0
        guard acceptsHits else { invalidateTargets(); return [] }
        let parentChanged = self.parent !== parent
        var next: [String: MapAccessibilityElement] = [:]
        var nextTargets: [String: Int] = [:]
        var children: [NSAccessibilityElement] = []
        for item in items {
            visitedCount += 1
            guard item.interactive, item.node.parent == focus, item.opacity > 0.5,
                  isCurrent(item.tile.id, item.node.path) else { continue }
            let path = item.node.path
            let existing = elements[path]
            let element = existing ?? MapAccessibilityElement(path: path, action: action)
            if existing == nil { createdCount += 1 }
            if existing == nil || parentChanged { element.setAccessibilityParent(parent) }
            // String == folds canonical Unicode spellings; the published label must
            // still reflect the current metadata's exact spelling.
            if element.name?.utf8.elementsEqual(item.node.name.utf8) != true || element.sizeText != item.sizeText {
                element.name = item.node.name; element.sizeText = item.sizeText
                element.setAccessibilityLabel("\(item.node.name), \(item.sizeText)")
            }
            if let frame = screenFrame(item.tile.rect), element.frame != frame {
                element.frame = frame; element.setAccessibilityFrame(frame)
            }
            next[path] = element; nextTargets[path] = item.tile.id; children.append(element)
            if children.count == 500 { break }
        }
        for (path, element) in elements where next[path] == nil { element.setAccessibilityParent(nil) }
        elements = next; targets = nextTargets; self.parent = parent
        return children
    }
}

@MainActor
private final class MapAccessibilityElement: NSAccessibilityElement {
    nonisolated let path: String
    nonisolated let action: @Sendable (String) -> Void
    var name: String?
    var sizeText: String?
    var frame: CGRect?
    init(path: String, action: @escaping @Sendable (String) -> Void) {
        self.path = path; self.action = action; super.init()
        setAccessibilityRole(.button); setAccessibilityEnabled(true)
    }
    nonisolated override func accessibilityPerformPress() -> Bool { action(path); return true }
}
