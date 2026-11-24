import Foundation
@testable import SpaceSnifferCore
import CoreGraphics

enum LegacyTreemap {
    /// Squarified treemap. Every positive item participates, including sub-pixel items.
    public static func layout(_ items: [(Int, Double)], in bounds: CGRect, control: ScanControl? = nil) -> [MapRect] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let sorted = items.filter { $0.1 > 0 && $0.1.isFinite }.sorted {
            $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1
        }
        let total = sorted.reduce(0) { $0 + $1.1 }
        guard total > 0, total.isFinite else { return [] }
        let scale = bounds.width * bounds.height / total
        var remaining = bounds; var row: [(Int, Double)] = []; var output: [MapRect] = []
        var rowSum = 0.0; var rowMin = Double.infinity; var rowMax = 0.0
        func worst(sum: Double, low: Double, high: Double, side: Double) -> Double {
            guard sum > 0, side > 0, low > 0 else { return .infinity }
            return max(side * side * high / (sum * sum), sum * sum / (side * side * low))
        }
        func place(_ values: [(Int, Double)]) {
            let sum = values.reduce(0) { $0 + $1.1 }
            if remaining.width >= remaining.height {
                let width = min(remaining.width, sum / max(remaining.height, 0.000001)); var y = remaining.minY
                for (id, area) in values {
                    let height = min(remaining.maxY - y, area / max(width, 0.000001))
                    output.append(MapRect(id: id, rect: CGRect(x: remaining.minX, y: y, width: width, height: max(0, height)))); y += height
                }
                remaining.origin.x += width; remaining.size.width = max(0, remaining.width - width)
            } else {
                let height = min(remaining.height, sum / max(remaining.width, 0.000001)); var x = remaining.minX
                for (id, area) in values {
                    let width = min(remaining.maxX - x, area / max(height, 0.000001))
                    output.append(MapRect(id: id, rect: CGRect(x: x, y: remaining.minY, width: max(0, width), height: height))); x += width
                }
                remaining.origin.y += height; remaining.size.height = max(0, remaining.height - height)
            }
        }
        for (index, item) in sorted.enumerated() {
            if index % 1024 == 0 && control?.isCancelled == true { return [] }
            let next = (item.0, item.1 * scale)
            let side = min(remaining.width, remaining.height)
            if !row.isEmpty && worst(sum: rowSum + next.1, low: min(rowMin, next.1), high: max(rowMax, next.1), side: side) > worst(sum: rowSum, low: rowMin, high: rowMax, side: side) {
                place(row); row = []; rowSum = 0; rowMin = .infinity; rowMax = 0
            }
            row.append(next); rowSum += next.1; rowMin = min(rowMin, next.1); rowMax = max(rowMax, next.1)
        }
        if !row.isEmpty { place(row) }
        return output
    }
}

extension LegacyTreemap {
    static func tiles(snapshot: ScanSnapshot, weights: [Int64], root: Int, depth: Int, selected: Int? = nil, in bounds: CGRect, control: ScanControl) -> [TreemapTile]? {
        guard snapshot.nodes.indices.contains(root), weights.count == snapshot.nodes.count else { return [] }
        // REA: refreshBitmap 0x4295a0 builds focus→selection path;
        // TTreeMapNode::layout 0x468db0 exposes that path and its immediate children beyond base depth.
        var selectionPath = Set<Int>()
        var cursor = selected
        while let id = cursor, snapshot.nodes.indices.contains(id) {
            selectionPath.insert(id)
            if id == root { break }
            cursor = snapshot.nodes[id].parent
        }
        if !selectionPath.contains(root) { selectionPath.removeAll() }
        var result: [TreemapTile] = []
        func visit(_ id: Int, rect: CGRect, level: Int) {
            guard !control.isCancelled, rect.width >= 2, rect.height >= 2 else { return }
            let box = rect.insetBy(dx: 1.5, dy: 1.5)
            guard box.width > 1, box.height > 1 else { return }
            let node = snapshot.nodes[id]
            let revealChildren = level < depth || selectionPath.contains(id)
            let expanded = node.isDirectory && revealChildren && box.width > 65 && box.height > 62
            result.append(TreemapTile(id: id, rect: box, expanded: expanded, level: level))
            if expanded {
                let area = CGRect(x: box.minX + 3, y: box.minY + 25, width: box.width - 6, height: box.height - 28)
                for tile in layout(node.children.map { ($0, Double(weights[$0])) }, in: area, control: control) {
                    visit(tile.id, rect: tile.rect, level: level + 1)
                }
            }
        }
        let area = bounds.insetBy(dx: 10, dy: 10)
        let node = snapshot.nodes[root]
        if node.isDirectory {
            for tile in layout(node.children.map { ($0, Double(weights[$0])) }, in: area, control: control) { visit(tile.id, rect: tile.rect, level: 1) }
        } else { visit(root, rect: area, level: 0) }
        return control.isCancelled ? nil : result
    }
}
