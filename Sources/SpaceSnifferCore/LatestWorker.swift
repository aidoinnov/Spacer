import Foundation

/// One running job and one pending job. New requests cancel obsolete work, never spawn an unbounded task list.
public final class LatestWorker<Result: Sendable>: @unchecked Sendable {
    private final class Job: @unchecked Sendable {
        struct Payload: Sendable {
            let operation: @Sendable (ScanControl) -> Result?
            let completion: @Sendable (Result) -> Void
        }
        let control: ScanControl
        let queuedAt = DispatchTime.now().uptimeNanoseconds
        // Only the serial consumer accesses payload after enqueueing. Empty it
        // synchronously so an idle async iterator cannot retain the last tree.
        private let payloadLock = NSLock()
        private var payload: Payload?
        init(control: ScanControl, operation: @escaping @Sendable (ScanControl) -> Result?, completion: @escaping @Sendable (Result) -> Void) {
            self.control = control
            payloadLock.lock()
            payload = Payload(operation: operation, completion: completion)
            payloadLock.unlock()
        }
        func run(stage: String) {
            payloadLock.lock()
            let payload = self.payload; self.payload = nil
            payloadLock.unlock()
            guard let payload else { return }
            guard !control.isCancelled else { WorkerTelemetry.shared.note(stage, cancelled: 1); return }
            let start = WorkerTelemetry.shared.begin(stage, queuedAt: queuedAt)
            let result = payload.operation(control)
            WorkerTelemetry.shared.end(stage, since: start, cancelled: control.isCancelled, failed: result == nil)
            if let result, !control.isCancelled { payload.completion(result) }
        }
        @discardableResult func discard() -> Bool {
            payloadLock.lock(); let hadPayload = payload != nil; payload = nil; payloadLock.unlock(); return hadPayload
        }
    }
    private final class Handoff: @unchecked Sendable {
        let lock = NSLock()
        var pending: Job?
    }
    private let lock: NSLock
    private let handoff: Handoff
    private var activeControl: ScanControl?
    private var stopped = false
    private let continuation: AsyncStream<Job>.Continuation
    private let task: Task<Void, Never>
    private let name: String
    public init(name: String = "worker.latest") {
        self.name = name
        let state = Handoff(); handoff = state; lock = state.lock
        let channel = AsyncStream<Job>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = channel.continuation
        task = Task.detached(priority: .userInitiated) {
            for await job in channel.stream {
                guard !Task.isCancelled else { break }
                // AsyncStream hands off the reference; this explicit producer /
                // consumer barrier also publishes its immutable lock/control fields.
                // Never hold the submission lock while executing user work.
                state.lock.withLock { if state.pending === job { state.pending = nil } }
                WorkerTelemetry.shared.record(name)
                job.run(stage: name)
            }
        }
    }
    public func submit(operation: @escaping @Sendable (ScanControl) -> Result?, completion: @escaping @Sendable (Result) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        WorkerTelemetry.shared.note(name, submitted: 1)
        activeControl?.cancel()
        if handoff.pending?.discard() == true { WorkerTelemetry.shared.note(name, coalesced: 1) }
        let control = ScanControl(); activeControl = control
        let job = Job(control: control, operation: operation, completion: completion)
        handoff.pending = job
        let result = continuation.yield(job)
        if case .terminated = result {
            if job.discard() { WorkerTelemetry.shared.note(name, cancelled: 1) }; handoff.pending = nil
        }
    }
    public func cancel() {
        lock.lock(); activeControl?.cancel()
        if handoff.pending?.discard() == true { WorkerTelemetry.shared.note(name, cancelled: 1) }
        handoff.pending = nil; lock.unlock()
    }
    public func shutdown() {
        lock.lock(); stopped = true; activeControl?.cancel()
        if handoff.pending?.discard() == true { WorkerTelemetry.shared.note(name, cancelled: 1) }
        handoff.pending = nil; continuation.finish(); task.cancel(); lock.unlock()
    }
    deinit { shutdown() }
}
