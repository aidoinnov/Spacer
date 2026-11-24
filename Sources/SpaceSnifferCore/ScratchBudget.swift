import Foundation
import Dispatch

public struct ScratchStatistics: Sendable {
    public var retainedBytes = 0
    public var chargedBytes = 0
    public var owners = 0
    public var active = 0
    public var peakActive = 0
    public var hits = 0
    public var misses = 0
    public var evictedBytes = 0
    public var pressureEvents = 0
    public let limit = 4_194_304
}

/// Idle ancestor buffers only. Active operation memory and published arrays are
/// not a pool and are not represented as a process-wide memory ceiling.
final class ScratchBudget: @unchecked Sendable {
    static let shared = ScratchBudget()
    private final class Holding {
        weak var owner: FilterScratch?
        let capacity: Int; let charge: Int
        init(_ owner: FilterScratch, capacity: Int, charge: Int) { self.owner = owner; self.capacity = capacity; self.charge = charge }
    }
    private let lock = NSLock()
    private var holders: [ObjectIdentifier: Holding] = [:]
    private var metrics = ScratchStatistics()
    private var generation: UInt64 = 0
    private var allowedAfter: UInt64 = 0
    private let pressureSource: any DispatchSourceMemoryPressure
    private init() {
        pressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        pressureSource.setEventHandler { [weak self] in self?.pressure() }; pressureSource.resume()
    }
    private func remove(_ id: ObjectIdentifier) {
        if let old = holders.removeValue(forKey: id) { metrics.retainedBytes -= old.capacity; metrics.chargedBytes -= old.charge }
        metrics.owners = holders.count
    }
    func checkout(_ owner: FilterScratch, capacity: Int, needed: Int) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        remove(ObjectIdentifier(owner)); metrics.active += 1; metrics.peakActive = max(metrics.peakActive, metrics.active)
        if needed > 0 { if capacity >= needed { metrics.hits += 1 } else { metrics.misses += 1 } }
        return generation
    }
    func finish(_ owner: FilterScratch, capacity: Int, limit: Int, epoch: UInt64, release: (Bool) -> Void) {
        lock.lock()
        let charge = max(65_536, capacity)
        let keep = capacity > 0 && capacity <= limit && epoch == generation && DispatchTime.now().uptimeNanoseconds >= allowedAfter && charge <= metrics.limit - metrics.chargedBytes
        if keep {
            holders[ObjectIdentifier(owner)] = Holding(owner, capacity: capacity, charge: charge)
            metrics.retainedBytes += capacity; metrics.chargedBytes += charge; metrics.owners = holders.count
        } else { metrics.evictedBytes += capacity }
        metrics.active -= 1
        // Publication and owner-unlock are atomic with respect to pressure's
        // holder snapshot. No filter work executes while holding this lock.
        release(keep); lock.unlock()
        withExtendedLifetime(owner) {}
    }
    func relinquish(_ owner: FilterScratch) { lock.lock(); remove(ObjectIdentifier(owner)); lock.unlock() }
    func snapshot() -> ScratchStatistics { lock.lock(); defer { lock.unlock() }; return metrics }
    func pressure() {
        lock.lock(); generation &+= 1; allowedAfter = DispatchTime.now().uptimeNanoseconds &+ 2_000_000_000
        let owners = holders.values.compactMap(\.owner)
        metrics.evictedBytes += metrics.retainedBytes; metrics.pressureEvents += 1
        holders.removeAll(); metrics.retainedBytes = 0; metrics.chargedBytes = 0; metrics.owners = 0
        lock.unlock()
        for owner in owners { owner.evictIfIdle() }
    }
}

public enum ScratchResources {
    public static func statistics() -> ScratchStatistics { ScratchBudget.shared.snapshot() }
}
