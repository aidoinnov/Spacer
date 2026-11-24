import Foundation

/// Native text report traversal (exportAll/exportNode/compareTo). Output goes to a
/// caller-owned sink; this type never opens files, retains jobs, or changes UI.
public enum ConfiguredReport {
    public enum ReportError: Error, Equatable { case invalidRoot, unsupportedSort(String), missingFormatter(String), outputLimit }
    public enum TimeField: Sendable { case created, modified, accessed }
    public enum TimePart: Sendable { case date, time, age }
    public struct Formatting: Sendable {
        public let decimalSeparator: Character
        public let time: (@Sendable (Date?, TimeField, TimePart, Date) throws -> String)?
        public init(decimalSeparator: Character = ".", time: (@Sendable (Date?, TimeField, TimePart, Date) throws -> String)? = nil) {
            self.decimalSeparator = decimalSeparator; self.time = time
        }
    }
    public struct Statistics: Sendable, Equatable { public let nodes: Int, files: Int, folders: Int, containers: Int, bytes: Int64 }
    private struct Counts {
        var nodes = 0, files = 0, folders = 0, containers = 0
        mutating func advance(_ node: DiskNode) {
            nodes += 1
            if NativeReportOrdering.isFile(node) { files += 1 }
            if NativeReportOrdering.isFolder(node) { folders += 1 }
            if NativeReportOrdering.isContainer(node) { containers += 1 }
        }
    }
    private struct Frame {
        let id: Int, depth: Int, positions: [Int]
        var next = 0, local = Counts()
    }
    /// Descriptive size 0x466b80: shifts by 1024, previous-unit remainder,
    /// one truncated decimal digit only when the remainder is nonzero. Not GB SI.
    public static func describeSize(_ bytes: Int64) -> String {
        let labels = ["b","KB","MB","GB","TB"]
        var whole = bytes, previous = bytes, unit = 0
        while whole > 1023, unit < 4 { previous = whole; whole >>= 10; unit += 1 }
        if unit > 0 {
            let remainder = previous - whole * 1024
            if remainder > 0 { return String(whole) + "." + String(remainder * 10 / 1024) + labels[unit] }
        }
        return String(whole) + labels[unit]
    }
    /// sortMode is a Mac extension for the existing logical view. Native fine
    /// sorting by "size" calls physical bytes; the default preserves that rule.
    public static func write<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, configuration: NativeConfiguration.ExportConfiguration,
            filter: ScanFilter, showHidden: Bool = true, root: Int = 0, sortMode: SizeMode = .allocated,
            formatting: Formatting = Formatting(), now: Date = Date(), maximumOutputBytes: Int64 = 1_073_741_824,
            control: ScanControl? = nil, to sink: inout S) throws -> Statistics {
        try check(control)
        guard maximumOutputBytes >= 0 else { throw ReportError.outputLimit }
        guard snapshot.nodes.indices.contains(root) else { throw ReportError.invalidRoot }
        let ordering = try NativeReportOrdering.Spec(configuration)
        let header = try NativeExportTemplate(configuration.headerFormat, control: control)
        let detail = try NativeExportTemplate(configuration.detailFormat, control: control)
        let footer = try NativeExportTemplate(configuration.footerFormat, control: control)
        let requested = header.referencedTags.union(detail.referencedTags).union(footer.referencedTags)
        guard let membership = filter.membership(in: snapshot, showHidden: showHidden, control: control, now: now) else { throw CancellationError() }
        let needsLogical = !requested.isDisjoint(with: ["size","sizebytes"]) || ordering.fine == .size && sortMode == .logical
        let needsAllocated = !requested.isDisjoint(with: ["disksize","disksizebytes"]) || ordering.fine == .size && sortMode == .allocated
        let logical = needsLogical ? filter.weights(in: snapshot, mode: .logical, included: membership, control: control) : []
        let allocated = needsAllocated ? filter.weights(in: snapshot, mode: .allocated, included: membership, control: control) : []
        try check(control)
        var selected = membership
        if selected.count > 1 {
            for id in stride(from: selected.count - 1, through: 1, by: -1) {
                if id % 128 == 0 { try check(control) }
                if selected[id], let parent = snapshot.nodes[id].parent { selected[parent] = true }
            }
        }
        let sortWeights = sortMode == .logical ? logical : allocated
        var totals = Counts(), outputBytes: Int64 = 0
        func values(_ template: NativeExportTemplate, id: Int, depth: Int, global: Counts, local: Counts) throws -> [String: String] {
            let node = snapshot.nodes[id]
            let isFile = NativeReportOrdering.isFile(node)
            var result: [String: String] = [:]
            for tag in template.referencedTags {
                try check(control)
                switch tag {
                case "file": result[tag] = node.name // Native differs from the manual's reversed file/filename descriptions.
                case "filename": result[tag] = node.name.lastIndex(of: ".").map { String(node.name[..<$0]) } ?? node.name
                case "fileext": result[tag] = node.name.lastIndex(of: ".").map { String(node.name[node.name.index(after:$0)...]) } ?? ""
                case "path": result[tag] = node.parent.map { snapshot.nodes[$0].path } ?? ""
                case "pathfile": result[tag] = node.path
                case "size": result[tag] = describeSize(logical[id])
                case "sizebytes": result[tag] = String(logical[id])
                case "disksize": result[tag] = describeSize(allocated[id])
                case "disksizebytes": result[tag] = String(allocated[id])
                case "isfile": result[tag] = isFile ? "true" : "false"
                case "isfolder": result[tag] = NativeReportOrdering.isFolder(node) ? "true" : "false"
                case "iscontainer": result[tag] = NativeReportOrdering.isContainer(node) ? "true" : "false"
                case "count": result[tag] = String(global.nodes)
                case "filecount": result[tag] = String(global.files)
                case "foldercount": result[tag] = String(global.folders)
                case "containercount": result[tag] = String(global.containers)
                case "localcount": result[tag] = String(local.nodes)
                case "localfilecount": result[tag] = String(local.files)
                case "localfoldercount": result[tag] = String(local.folders)
                case "localcontainercount": result[tag] = String(local.containers)
                case "containsfiles": result[tag] = node.children.contains { selected[$0] && NativeReportOrdering.isFile(snapshot.nodes[$0]) } ? "true" : "false"
                case "containsfolders": result[tag] = node.children.contains { selected[$0] && NativeReportOrdering.isFolder(snapshot.nodes[$0]) } ? "true" : "false"
                case "containscontainers": result[tag] = node.children.contains { selected[$0] && NativeReportOrdering.isContainer(snapshot.nodes[$0]) } ? "true" : "false"
                case "nestinglevel": result[tag] = String(depth)
                default:
                    guard NativeExportTemplate.knownTags.contains(tag) else { continue }
                    if !isFile { result[tag] = "*VOID*"; continue }
                    guard let time = formatting.time else { throw ReportError.missingFormatter(tag) }
                    let field: TimeField = tag.hasPrefix("filecreate") ? .created : tag.hasPrefix("fileaccess") ? .accessed : .modified
                    let date: Date? = field == .created ? node.created : field == .accessed ? node.accessed : node.modified
                    let part: TimePart = tag.hasSuffix("date") ? .date : tag.hasSuffix("time") ? .time : .age
                    result[tag] = try time(date, field, part, now)
                }
            }
            return result
        }
        func emit(_ template: NativeExportTemplate, id: Int, depth: Int, global: Counts, local: Counts) throws {
            try check(control)
            let row = try template.render(values: values(template, id: id, depth: depth, global: global, local: local), nestingLevel: depth,
                lineBreaks: .fileText, decimalSeparator: formatting.decimalSeparator, control: control)
            let count = Int64(row.utf8.count)
            guard count <= maximumOutputBytes - outputBytes else { throw ReportError.outputLimit }
            try sink.utf8(row); outputBytes += count
        }
        guard NativeReportOrdering.isPhysical(snapshot.nodes[root]) else { return Statistics(nodes: 0, files: 0, folders: 0, containers: 0, bytes: 0) }
        // Native header is a root-only exportNode call before counters reset.
        var headerCounts = Counts(); headerCounts.advance(snapshot.nodes[root])
        try emit(header, id: root, depth: 0, global: headerCounts, local: Counts())
        totals.advance(snapshot.nodes[root]); try emit(detail, id: root, depth: 0, global: totals, local: Counts())
        var stack = [Frame(id: root, depth: 0, positions: NativeReportOrdering.positions(snapshot, root: root, weights: sortWeights, spec: ordering, includes: { selected[$0] }))]
        while var frame = stack.popLast() {
            try check(control)
            guard frame.next < frame.positions.count else { continue }
            let id = snapshot.nodes[frame.id].children[frame.positions[frame.next]]
            frame.next += 1; frame.local.advance(snapshot.nodes[id]); let local = frame.local
            let depth = frame.depth + 1; stack.append(frame)
            guard NativeReportOrdering.isPhysical(snapshot.nodes[id]) else { continue }
            totals.advance(snapshot.nodes[id]); try emit(detail, id: id, depth: depth, global: totals, local: local)
            let positions = NativeReportOrdering.positions(snapshot, root: id, weights: sortWeights, spec: ordering, includes: { selected[$0] })
            if !positions.isEmpty { stack.append(Frame(id: id, depth: depth, positions: positions)) }
        }
        // Footer's native root-only call increments root counters once more.
        // Returned statistics describe the detail pass; footer tags see that increment.
        var footerCounts = totals; footerCounts.advance(snapshot.nodes[root])
        try emit(footer, id: root, depth: 0, global: footerCounts, local: Counts())
        return Statistics(nodes: totals.nodes, files: totals.files, folders: totals.folders, containers: totals.containers, bytes: outputBytes)
    }
    private static func check(_ control: ScanControl?) throws { if Task.isCancelled || control?.isCancelled == true { throw CancellationError() } }
}

/// One comparator/arrival-order contract for the legacy simple preset and the
/// configurable report. IDs are identity, never a substitute for child position.
enum NativeReportOrdering {
    enum Block { case none, files, folders }
    enum Fine { case none, size, name }
    struct Spec {
        let block: Block, fine: Fine, descending: Bool
        static let simple = Spec(block: .files, fine: .size, descending: true)
        init(block: Block, fine: Fine, descending: Bool) { self.block = block; self.fine = fine; self.descending = descending }
        init(_ configuration: NativeConfiguration.ExportConfiguration) throws {
            switch configuration.blockSorting { case "", "none": block = .none; case "files": block = .files; case "folders": block = .folders; default: throw ConfiguredReport.ReportError.unsupportedSort(configuration.blockSorting) }
            switch configuration.fineSorting { case "", "none": fine = .none; case "size": fine = .size; case "name": fine = .name; default: throw ConfiguredReport.ReportError.unsupportedSort(configuration.fineSorting) }
            switch configuration.fineSortingDirection { case "", "asc": descending = false; case "desc": descending = true; default: throw ConfiguredReport.ReportError.unsupportedSort(configuration.fineSortingDirection) }
        }
    }
    static func isFile(_ node: DiskNode) -> Bool { node.nativeType.map { $0 == 2 } ?? !node.isDirectory }
    static func isFolder(_ node: DiskNode) -> Bool { node.nativeType.map { $0 == 3 } ?? node.isDirectory }
    static func isContainer(_ node: DiskNode) -> Bool { node.nativeType.map { $0 == 1 || $0 == 3 } ?? node.isDirectory }
    static func isPhysical(_ node: DiskNode) -> Bool { node.nativeType.map { (1...3).contains($0) } ?? true }
    static func positions(_ snapshot: ScanSnapshot, root: Int, weights: [Int64], spec: Spec, includes: (Int) -> Bool) -> [Int] {
        let children = snapshot.nodes[root].children
        let positions = children.indices.filter { includes(children[$0]) }
        if spec.block == .none, spec.fine == .none { return positions }
        return positions.sorted { lhs, rhs in
            let a = snapshot.nodes[children[lhs]], b = snapshot.nodes[children[rhs]]
            if spec.block == .files || spec.block == .folders {
                let ac = isContainer(a), bc = isContainer(b), af = isFile(a), bf = isFile(b)
                if ac && bf { return spec.block == .folders }
                if af && bc { return spec.block == .files }
            }
            if spec.fine == .size {
                let av = weights.indices.contains(a.id) ? weights[a.id] : a.allocatedBytes
                let bv = weights.indices.contains(b.id) ? weights[b.id] : b.allocatedBytes
                if av != bv { return spec.descending ? av > bv : av < bv }
            } else if spec.fine == .name, !a.name.utf16.elementsEqual(b.name.utf16) {
                return spec.descending ? b.name.utf16.lexicographicallyPrecedes(a.name.utf16) : a.name.utf16.lexicographicallyPrecedes(b.name.utf16)
            }
            return lhs > rhs // Native inserts an equal incoming child before existing ones.
        }
    }
}
