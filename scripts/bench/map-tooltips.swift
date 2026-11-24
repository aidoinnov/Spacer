import AppKit
import SpaceSnifferCore

@main enum TooltipProbe {
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]; let count = Int(CommandLine.arguments[2])!; let moving = CommandLine.arguments[3] == "moving"
        let fixture = (1...count).map { id in
            MapItem(tile: TreemapTile(id: id, rect: CGRect(x: id, y: 2, width: 30, height: 40), expanded: false, level: 0),
                node: DiskNode(id: id, parent: 0, path: "/root/\(id)", name: "node-\(id)"), parentPath: "/root", sizeText: "1 KB", sizeWidth: 20, tag: 0, category: .other)
        }
        let view = NSView(); let registry = MapTooltipRegistry()
        var adds = 0; var rebuilds = 0; var checksum = 0.0
        let start = ContinuousClock.now
        for frame in 0..<60 {
            autoreleasepool {
                let visible = moving ? fixture.map { item -> MapItem in
                    var value = item
                    value.tile = TreemapTile(id: item.tile.id, rect: item.tile.rect.offsetBy(dx: Double(frame), dy: 0), expanded: false, level: 0)
                    return value
                } : fixture
                if mode == "legacy" {
                    view.removeAllToolTips(); rebuilds += 1
                    for item in visible where item.interactive && item.opacity > 0.5 && item.tile.rect.width > 15 && item.tile.rect.height > 15 {
                        _ = view.addToolTip(item.tile.rect, owner: view, userData: UnsafeMutableRawPointer(bitPattern: item.tile.id + 1)); adds += 1
                    }
                } else {
                    registry.update(visible, view: view, acceptsHits: true,
                        isCurrent: { id, path in fixture[id-1].node.path == path })
                }
                checksum += visible.first!.tile.rect.minX + visible.last!.tile.rect.maxX
            }
        }
        let duration = start.duration(to: .now).components
        if mode != "legacy" { adds = registry.addCount; rebuilds = registry.rebuildCount }
        let retained = registry.registeredCount
        registry.invalidate(); view.removeAllToolTips()
        let row: [String: Any] = ["mode":mode,"items":count,"scenario":moving ? "moving" : "stationary","updates":60,
            "seconds":Double(duration.seconds)+Double(duration.attoseconds)/1e18,"native_adds":adds,"rebuilds":rebuilds,
            "registered_before_clear":retained,"registered_after_clear":registry.registeredCount,"checksum":checksum]
        print(String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
    }
}
