import Foundation
import Darwin
@testable import SpaceSnifferCore

// Experimental candidates only: never linked into the application target.
fileprivate final class CandidateNode: @unchecked Sendable { var value: DiskNode; init(_ value: DiskNode) { self.value = value } }
fileprivate final class CandidatePage: @unchecked Sendable { var values: [DiskNode] = [] }
struct CandidateReader: Sendable {
    fileprivate enum Storage: Sendable { case current(NodeTable), pages([CandidatePage]), nodes([CandidateNode]) }
    fileprivate let storage: Storage
    let count: Int
    func node(_ id: Int) -> DiskNode {
        switch storage {
        case .current(let table): return table[id]
        case .pages(let pages): return pages[id / 1024].values[id % 1024]
        case .nodes(let nodes): return nodes[id].value
        }
    }
    func materialized() -> [DiskNode] { (0..<count).map { node($0) } }
    func adapted() -> NodeTable {
        if case .current(let value) = storage { return value }
        return NodeTable(materialized())
    }
}
struct CandidateStatistics {
    var hits = 0; var misses = 0; var busyExclusions = 0
    var retainedCharge = 0; var evictedCharge = 0
}
final class PoolCandidate: @unchecked Sendable {
    enum Kind: String, CaseIterable { case current, pages, nodes }
    private let lock = NSLock()
    private let kind: Kind
    private let budget: Int
    private var pages: [CandidatePage] = []
    private var nodes: [CandidateNode] = []
    private var metrics = CandidateStatistics()
    init(_ kind: Kind, budget: Int = 4_194_304) { self.kind = kind; self.budget = budget }
    private func nodeCharge(_ node: CandidateNode) -> Int { max(1, Int(malloc_size(Unmanaged.passUnretained(node).toOpaque()))) }
    private func pageCharge(_ page: CandidatePage) -> Int { max(1, Int(malloc_size(Unmanaged.passUnretained(page).toOpaque()))) + page.values.capacity * MemoryLayout<DiskNode>.stride + 64 }
    private var empty: DiskNode { DiskNode(id: -1, parent: nil, path: "", name: "") }
    @inline(never) func build(_ input: [DiskNode]) -> CandidateReader {
        lock.lock(); defer { lock.unlock() }
        if kind == .current { return CandidateReader(storage: .current(NodeTable(input)), count: input.count) }
        if kind == .nodes {
            var free: [Int] = []
            for index in nodes.indices {
                if isKnownUniquelyReferenced(&nodes[index]) { nodes[index].value = empty; free.append(index) }
                else { metrics.busyExclusions += 1 }
            }
            var result: [CandidateNode] = []; result.reserveCapacity(input.count)
            for value in input {
                if let index = free.popLast() { nodes[index].value = value; result.append(nodes[index]); metrics.hits += 1 }
                else {
                    let node = CandidateNode(value); let charge = nodeCharge(node)
                    metrics.misses += 1
                    if charge <= budget - metrics.retainedCharge { nodes.append(node); metrics.retainedCharge += charge }
                    result.append(node)
                }
            }
            return CandidateReader(storage: .nodes(result), count: input.count)
        }
        var free: [Int] = []
        for index in pages.indices {
            if isKnownUniquelyReferenced(&pages[index]) { pages[index].values.removeAll(keepingCapacity: true); free.append(index) }
            else { metrics.busyExclusions += 1 }
        }
        var result: [CandidatePage] = []
        for offset in stride(from: 0, to: input.count, by: 1024) {
            let page: CandidatePage
            if let index = free.popLast() { page = pages[index]; metrics.hits += 1 }
            else { page = CandidatePage(); page.values.reserveCapacity(1024); metrics.misses += 1 }
            page.values.append(contentsOf: input[offset..<min(input.count, offset + 1024)])
            if !pages.contains(where: { $0 === page }) {
                let charge = pageCharge(page)
                if charge <= budget - metrics.retainedCharge { pages.append(page); metrics.retainedCharge += charge }
            }
            result.append(page)
        }
        return CandidateReader(storage: .pages(result), count: input.count)
    }
    func evict() {
        lock.lock(); metrics.evictedCharge += metrics.retainedCharge; pages.removeAll(); nodes.removeAll(); metrics.retainedCharge = 0; lock.unlock()
    }
    func statistics() -> CandidateStatistics { lock.lock(); defer { lock.unlock() }; return metrics }
}
