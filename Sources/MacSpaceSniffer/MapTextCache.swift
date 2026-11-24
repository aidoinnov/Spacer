import AppKit
import SpaceSnifferCore

/// Text for one presentation, never a tree-wide path/name cache.
@MainActor
final class MapTextCache {
    private struct Entry {
        let name: String; let directory: Bool; let link: Bool; let bytes: Int64?
        let title: String; let size: String; let width: CGFloat
    }
    private var entries: [String: Entry] = [:]
    private(set) var pointSize: CGFloat
    private(set) var formattingCount = 0
    private(set) var measurementCount = 0
    private(set) var titleCount = 0
    private(set) var estimatedUTF8Bytes = 0
    let entryLimit: Int
    let byteLimit: Int
    private var font: NSFont
    private(set) var titleAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var folderAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var headerSizeAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var leafSizeAttributes: [NSAttributedString.Key: Any] = [:]
    var retainedCount: Int { entries.count }
    init(pointSize: CGFloat = 11, entryLimit: Int = 4096, byteLimit: Int = 1_048_576) {
        self.pointSize = pointSize; self.entryLimit = max(0, entryLimit); self.byteLimit = max(0, byteLimit)
        font = NSFont.systemFont(ofSize: pointSize); rebuildStyles()
    }
    private func rebuildStyles() {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
        let style = paragraph.copy() as! NSParagraphStyle
        func attributes(_ weight: NSFont.Weight, _ alpha: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: NSFont.systemFont(ofSize: pointSize, weight: weight), .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: style]
        }
        titleAttributes = attributes(.regular, 0.9); folderAttributes = attributes(.medium, 0.9)
        headerSizeAttributes = attributes(.regular, 0.65); leafSizeAttributes = attributes(.regular, 0.56)
    }
    func setPointSize(_ value: CGFloat) {
        guard value > 0, value.isFinite, value != pointSize else { return }
        pointSize = value; font = NSFont.systemFont(ofSize: value); clear(); rebuildStyles()
    }
    func clear() { entries.removeAll(); estimatedUTF8Bytes = 0 }
    func prepare(_ items: [MapItem]) -> [MapItem] {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { WorkerTelemetry.shared.observe("paint.text.prepare", nanoseconds: DispatchTime.now().uptimeNanoseconds &- started) }
        var next: [String: Entry] = [:]; var bytes = 0
        let result = items.map { original -> MapItem in
            var item = original; let node = item.node
            let old = entries[node.path]
            let sameName = old?.name.utf8.elementsEqual(node.name.utf8) == true
            let title: String
            if sameName, old?.directory == node.isDirectory, old?.link == node.isSymbolicLink { title = old!.title }
            else { title = WorkerTelemetry.shared.measure("paint.text.title") { (node.isDirectory ? "▸ " : node.isSymbolicLink ? "↗ " : "") + node.name }; titleCount += 1 }
            let size: String; let width: CGFloat
            if let old, old.bytes == item.displayBytes,
               item.displayBytes != nil || old.size.utf8.elementsEqual(item.sizeText.utf8) && old.width == item.sizeWidth {
                size = old.size; width = old.width
            } else if let value = item.displayBytes {
                size = WorkerTelemetry.shared.measure("paint.text.format") { formattedBytes(value) }; formattingCount += 1
                width = WorkerTelemetry.shared.measure("paint.text.measure") { (size as NSString).size(withAttributes: [.font: font]).width }; measurementCount += 1
            } else {
                size = item.sizeText; width = item.sizeWidth
            }
            item.titleText = title; item.sizeText = size; item.sizeWidth = width
            let cost = node.path.utf8.count + node.name.utf8.count + title.utf8.count + size.utf8.count
            if next.count < entryLimit, cost <= byteLimit - bytes {
                next[node.path] = Entry(name: node.name, directory: node.isDirectory, link: node.isSymbolicLink, bytes: item.displayBytes,
                    title: title, size: size, width: width); bytes += cost
            }
            return item
        }
        entries = next; estimatedUTF8Bytes = bytes
        return result
    }
}
