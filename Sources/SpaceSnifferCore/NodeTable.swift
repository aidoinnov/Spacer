import Foundation

/// macOS value-snapshot storage. Copying a snapshot shares immutable pages;
/// mutation copies only the touched page instead of the complete node array.
/// Page size is a storage choice, not a reconstructed Windows engine rule.
public struct NodeTable: RandomAccessCollection, MutableCollection, ExpressibleByArrayLiteral, Codable, Sendable {
    public typealias Index = Int
    private static let pageSize = 1024
    private var pages: [[DiskNode]] = []
    public private(set) var count = 0
    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
    /// Both live value snapshots share the same outer COW buffer. Any node/page
    /// mutation first makes that buffer unique; pointers never escape this call.
    public func sharesStorage(with other: NodeTable) -> Bool {
        guard count == other.count, pages.count == other.pages.count else { return false }
        return pages.withUnsafeBufferPointer { lhs in
            other.pages.withUnsafeBufferPointer { rhs in lhs.baseAddress == rhs.baseAddress }
        }
    }
    /// Conservative dirty proof from immutable COW pages. Rebuilt/dense tables
    /// fall back before comparing every node. No stored raw addresses.
    func differingNodeIDs(from other: NodeTable, control: ScanControl) -> [Int]? {
        guard count == other.count, pages.count == other.pages.count else { return nil }
        let pageLimit = Swift.min(8, Swift.max(1, pages.count / 8))
        var changedPages: [Int] = []
        for index in pages.indices {
            if control.isCancelled { return nil }
            let same = pages[index].withUnsafeBufferPointer { lhs in other.pages[index].withUnsafeBufferPointer { rhs in lhs.count == rhs.count && lhs.baseAddress == rhs.baseAddress } }
            if !same { changedPages.append(index); if changedPages.count > pageLimit { return nil } }
        }
        let limit = Swift.min(4096, Swift.max(32, count / 16)); var result: [Int] = []
        for page in changedPages {
            guard pages[page].count == other.pages[page].count else { return nil }
            for slot in pages[page].indices {
                if slot % 128 == 0 && control.isCancelled { return nil }
                let lhs = pages[page][slot]; let rhs = other.pages[page][slot]
                if lhs != rhs || !lhs.name.utf8.elementsEqual(rhs.name.utf8) || !lhs.path.utf8.elementsEqual(rhs.path.utf8) {
                    result.append(page * Self.pageSize + slot)
                    if result.count > limit { return nil }
                }
            }
        }
        return result
    }
    public init() {}
    public init(_ nodes: [DiskNode]) {
        reserveCapacity(nodes.count)
        for node in nodes { append(node) }
    }
    public init(arrayLiteral elements: DiskNode...) { self.init(elements) }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }
    public func index(_ i: Int, offsetBy distance: Int) -> Int { i + distance }
    public func distance(from start: Int, to end: Int) -> Int { end - start }
    public subscript(index: Int) -> DiskNode {
        _read {
            precondition(index >= 0 && index < count)
            yield pages[index / Self.pageSize][index % Self.pageSize]
        }
        set {
            precondition(index >= 0 && index < count)
            pages[index / Self.pageSize][index % Self.pageSize] = newValue
        }
        _modify {
            precondition(index >= 0 && index < count)
            yield &pages[index / Self.pageSize][index % Self.pageSize]
        }
    }
    public mutating func reserveCapacity(_ capacity: Int) {
        pages.reserveCapacity(capacity / Self.pageSize + (capacity % Self.pageSize == 0 ? 0 : 1))
    }
    public mutating func append(_ node: DiskNode) {
        if count % Self.pageSize == 0 {
            var page: [DiskNode] = []; page.reserveCapacity(Self.pageSize); pages.append(page)
        }
        pages[pages.count - 1].append(node); count += 1
    }
    /// One CoW/access scope per ancestor. The page remains owned by this table;
    /// previously published snapshots retain their unchanged page values.
    mutating func addObservedBytes(logical: Int64, allocated: Int64, startingAt parent: Int?) {
        var ancestor = parent
        let nodeCount = count
        while let id = ancestor {
            precondition(id >= 0 && id < nodeCount)
            let pageIndex = id / Self.pageSize
            // Array establishes unique CoW ownership before lending this
            // nonescaping buffer. No pointer survives this lexical scope.
            pages[pageIndex].withUnsafeMutableBufferPointer { page in
                while let current = ancestor, current / Self.pageSize == pageIndex {
                    precondition(current >= 0 && current < nodeCount)
                    let slot = current % Self.pageSize
                    page[slot].logicalBytes += logical
                    page[slot].allocatedBytes += allocated
                    ancestor = page[slot].parent
                }
            }
        }
    }
    public mutating func removeAll() { pages.removeAll(); count = 0 }
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.init()
        if let count = container.count { reserveCapacity(count) }
        while !container.isAtEnd { append(try container.decode(DiskNode.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for node in self { try container.encode(node) }
    }
}
