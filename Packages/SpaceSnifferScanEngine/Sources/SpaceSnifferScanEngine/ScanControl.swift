import Foundation

public final class ScanControl: @unchecked Sendable {
    // Hot cancellation reads retain the original NSLock. The separate
    // condition is used only by retry waits. cancel releases the state lock
    // before acquiring the condition, so there is no reverse lock ordering.
    private let lock = NSLock()
    private let retryCondition = NSCondition()
    private var stopped = false
    public init() {}
    public func cancel() {
        lock.lock(); stopped = true; lock.unlock()
        retryCondition.lock(); retryCondition.broadcast(); retryCondition.unlock()
    }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    public func waitForRetry(_ delay: TimeInterval) -> Bool {
        retryCondition.lock(); defer { retryCondition.unlock() }
        let deadline = Date(timeIntervalSinceNow: delay)
        while !isCancelled, delay > 0 {
            if !retryCondition.wait(until: deadline) { break }
        }
        return !isCancelled
    }
}

