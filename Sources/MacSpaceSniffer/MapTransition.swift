import Foundation
import CoreGraphics
import SpaceSnifferCore

/// Presentation cache owned by MapCanvas. Paths remain stable when a scan rebuilds numeric node IDs.
struct MapItem {
    var tile: TreemapTile
    let node: DiskNode
    let parentPath: String?
    var sizeText: String
    var sizeWidth: CGFloat
    let tag: Int
    let category: FileCategory
    var opacity: Double = 1
    var interactive = true
    var displayBytes: Int64?
    var titleText: String?
}

struct MapTransition {
    struct Track {
        var item: MapItem
        let from: CGRect
        let to: CGRect
        let fromOpacity: Double
        let toOpacity: Double
    }
    static func sameLayout(_ lhs: [MapItem], _ rhs: [MapItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let old = Dictionary(uniqueKeysWithValues: lhs.map { ($0.node.path, $0.tile) })
        return rhs.allSatisfy { item in
            guard let previous = old[item.node.path] else { return false }
            return previous.rect == item.tile.rect && previous.expanded == item.tile.expanded
        }
    }
    let started: TimeInterval
    let tracks: [Track]

    init(from oldItems: [MapItem], to newItems: [MapItem], at time: TimeInterval) {
        started = time
        let old = Dictionary(uniqueKeysWithValues: oldItems.map { ($0.node.path, $0) })
        let newPaths = Set(newItems.map { $0.node.path })
        var result: [Track] = []
        // Target nodes follow the final hierarchy, so folder headers remain behind their children.
        for item in newItems {
            if let previous = old[item.node.path] {
                result.append(Track(item: item, from: previous.tile.rect, to: item.tile.rect,
                                    fromOpacity: previous.opacity, toOpacity: 1))
            } else {
                let box = item.tile.rect
                let collapsed = CGRect(x: box.midX, y: box.midY, width: 0, height: 0)
                result.append(Track(item: item, from: collapsed, to: box, fromOpacity: 0, toOpacity: 1))
            }
        }
        for item in oldItems where !newPaths.contains(item.node.path) {
            var outgoing = item; outgoing.interactive = false
            result.append(Track(item: outgoing, from: item.tile.rect, to: item.tile.rect,
                                fromOpacity: item.opacity, toOpacity: 0))
        }
        tracks = result
    }
    func items(at time: TimeInterval) -> [MapItem] {
        let p = TreemapMotion.progress((time - started) / TreemapMotion.duration)
        return tracks.compactMap { track in
            let opacity = track.fromOpacity + (track.toOpacity - track.fromOpacity) * p
            guard opacity > 0.005 else { return nil }
            var result = track.item
            result.tile = TreemapTile(id: track.item.tile.id,
                rect: TreemapMotion.interpolate(from: track.from, to: track.to, progress: p),
                expanded: track.item.tile.expanded, level: track.item.tile.level)
            result.opacity = opacity
            return result
        }
    }
    func isFinished(at time: TimeInterval) -> Bool { time - started >= TreemapMotion.duration }
}
