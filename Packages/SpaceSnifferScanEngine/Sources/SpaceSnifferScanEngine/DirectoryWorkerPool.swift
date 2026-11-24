import Foundation

public final class DirectoryWorkerPool<Output: Sendable>: @unchecked Sendable {
    private struct Job: Sendable {
        let control: ScanControl
        let ticket: DirectoryReadTicket<Output>
        let operation: @Sendable () -> Output
    }
    private let condition = NSCondition()
    private let workers: Int
    private let capacity: Int
    private let budget: DirectoryIOBudget
    private let cancelledOutput: @Sendable () -> Output
    private let configureWorker: @Sendable (Thread, Int) -> Void
    private var pending: [Job] = []
    // Queue, flags and all counters are protected by condition. A stop request
    // closes admission; drain additionally waits for reader and delivery exit.
    private var shutdownRequested = false
    private var cancelledDeliveries = 0
    private var live = 0
    private var active = 0
    public init(workers: Int, capacity: Int, budget: DirectoryIOBudget,
                cancelledOutput: @escaping @Sendable () -> Output,
                configureWorker: @escaping @Sendable (Thread, Int) -> Void = { _, _ in }) {
        precondition(workers > 0 && capacity > 0)
        self.workers = workers; self.capacity = capacity; self.budget = budget
        self.cancelledOutput = cancelledOutput; self.configureWorker = configureWorker
    }
    public func submit(control: ScanControl, operation: @escaping @Sendable () -> Output) -> DirectoryReadTicket<Output>? {
        condition.lock()
        guard !shutdownRequested, pending.count < capacity else { condition.unlock(); return nil }
        let ticket = DirectoryReadTicket<Output>()
        pending.append(Job(control: control, ticket: ticket, operation: operation))
        let firstIndex = live
        let launchCount = min(workers - live, max(0, pending.count - (live - active)))
        live += launchCount
        condition.signal(); condition.unlock()
        if launchCount > 0 {
            for index in firstIndex..<(firstIndex + launchCount) {
                let thread = Thread { [self] in run() }
                thread.name = "sniffer.directory.\(index)"
                configureWorker(thread, index)
                thread.start()
            }
        }
        return ticket
    }
    /// Static dispatch once per folder; no per-entry protocol/object cost.
    public func submit<Reader: DirectoryBatchReader>(reader: Reader, path: String,
                                                    control: ScanControl) -> DirectoryReadTicket<Output>? where Reader.Output == Output {
        submit(control: control) { reader.readDirectory(at: path, control: control) }
    }
    private func run() {
        while true {
            condition.lock()
            while pending.isEmpty, !shutdownRequested { condition.wait() }
            if pending.isEmpty, shutdownRequested { live -= 1; condition.broadcast(); condition.unlock(); return }
            let job = pending.removeFirst(); active += 1; condition.unlock()
            let result: Output
            if let value = budget.withPermit(control: job.control, operation: job.operation) {
                result = value
            } else { result = cancelledOutput() }
            condition.lock(); active -= 1; condition.broadcast(); condition.unlock()
            job.ticket.finish(result) // Counters, permit and FDs settle first.
        }
    }
    public func cancelQueued(control: ScanControl) {
        guard control.isCancelled else { return }
        condition.lock()
        let cancelled = pending.filter { $0.control === control }
        pending.removeAll { $0.control === control }
        cancelledDeliveries += cancelled.count
        condition.unlock()
        for job in cancelled { job.ticket.finish(cancelledOutput()) }
        // Keep client closures/results alive until after accounting and unlock.
        // Their destruction must not execute while holding the pool condition.
        withExtendedLifetime(cancelled) {
            condition.lock()
            cancelledDeliveries -= cancelled.count
            precondition(cancelledDeliveries >= 0)
            condition.broadcast(); condition.unlock()
        }
    }
    /// Nonblocking: safe for an operation to request its own pool's stop.
    /// Already accepted operations still settle; no new work is admitted.
    public func requestShutdown() {
        condition.lock(); shutdownRequested = true; condition.broadcast(); condition.unlock()
    }
    /// Coordinator-only drain. Never call from this pool's operation/configure/
    /// cancellation callbacks; use requestShutdown there instead.
    public func shutdown() {
        requestShutdown()
        condition.lock()
        while live > 0 || cancelledDeliveries > 0 { condition.wait() }
        condition.unlock()
    }
    /// Native-work counts alone do not imply termination: cancelled deliveries
    /// can still be pending after the last reader exits.
    public var isTerminated: Bool {
        condition.lock(); defer { condition.unlock() }
        return shutdownRequested && live == 0 && cancelledDeliveries == 0 && active == 0 && pending.isEmpty
    }
    public var observation: (active: Int, queued: Int, live: Int) {
        condition.lock(); defer { condition.unlock() }; return (active, pending.count, live)
    }
}
