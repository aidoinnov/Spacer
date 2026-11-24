import Foundation

public final class DirectoryIOBudget: @unchecked Sendable {
    private let condition = NSCondition()
    public let limit: Int
    private var active = 0
    private var peak = 0
    public init(limit: Int) { precondition(limit > 0); self.limit = limit }
    public func acquire(control: ScanControl) -> Bool {
        condition.lock(); defer { condition.unlock() }
        while active == limit, !control.isCancelled { _ = condition.wait(until: Date(timeIntervalSinceNow: 0.02)) }
        guard !control.isCancelled else { return false }
        active += 1; peak = max(peak, active); return true
    }
    /// Stack-scoped permit: no allocation, and Swift errors always release it.
    /// nil means admission was cancelled; a successful optional nil stays .some(nil).
    @inlinable public func withPermit<Value>(control: ScanControl,
        operation: () throws -> Value) rethrows -> Value? {
        guard acquire(control: control) else { return nil }
        defer { release() }
        return try operation()
    }
    public func release() {
        condition.lock(); precondition(active > 0); active -= 1; condition.broadcast(); condition.unlock()
    }
    public var observation: (active: Int, peak: Int) { condition.lock(); defer { condition.unlock() }; return (active, peak) }
}

