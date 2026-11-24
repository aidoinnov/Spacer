import Foundation

public struct ScanAdmissionStatistics: Sendable {
    public let limit: Int
    public let capacity: Int
    public let active: Int
    public let queued: Int
    public let peakActive: Int
    public let started: Int
    public let finished: Int
    public let cancelledBeforeStart: Int
    public let rejected: Int
}
public enum ScanAdmissionError: Error { case capacity, stopped }
public enum ScanExecutionResult: Sendable {
    case finished(ScanSnapshot)
    case cancelledBeforeStart
}

/// Process-wide scan admission. Blocking filesystem work is dispatched outside
/// Swift's cooperative executor. This limits operations, not physical OS threads.
/// W16 supplies the reuse/admission principle; queue limits and Dispatch are Mac policy.
public final class ScanAdmission: @unchecked Sendable {
    public static let shared = ScanAdmission(limit: 8)
    private struct Job: Sendable {
        let id: UUID
        let control: ScanControl
        let operation: @Sendable () -> ScanSnapshot
        let completion: @Sendable (ScanExecutionResult) -> Void
        let queuedAt = DispatchTime.now().uptimeNanoseconds
    }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "space-sniffer.scan-io", qos: .utility, attributes: .concurrent)
    private let limit: Int
    private let capacity: Int
    private var pending: [Job] = []
    private var running: [UUID: ScanControl] = [:]
    private var stopped = false
    private var peakActive = 0
    private var started = 0
    private var finished = 0
    private var cancelledBeforeStart = 0
    private var rejected = 0
    public init(limit: Int, capacity: Int = 64) {
        precondition(limit > 0 && capacity >= 0)
        self.limit = limit; self.capacity = capacity
    }
    @discardableResult
    public func submit(control: ScanControl, operation: @escaping @Sendable () -> ScanSnapshot,
                       completion: @escaping @Sendable (ScanExecutionResult) -> Void) throws -> UUID {
        let job = Job(id: UUID(), control: control, operation: operation, completion: completion)
        lock.lock()
        guard !stopped else { rejected += 1; lock.unlock(); throw ScanAdmissionError.stopped }
        if running.count < limit {
            admit(job); lock.unlock(); dispatch(job)
        } else {
            guard pending.count < capacity else { rejected += 1; lock.unlock(); throw ScanAdmissionError.capacity }
            pending.append(job); lock.unlock()
        }
        return job.id
    }
    /// Called only while holding lock. Admission reserves the slot before dispatch.
    private func admit(_ job: Job) {
        running[job.id] = job.control; started += 1
        peakActive = max(peakActive, running.count)
    }
    private func dispatch(_ job: Job) {
        queue.async { [self] in
            WorkerTelemetry.shared.record("scan.worker")
            let startedAt = WorkerTelemetry.shared.begin("scan.worker", queuedAt: job.queuedAt)
            var result: ScanExecutionResult
            if job.control.isCancelled { result = .cancelledBeforeStart }
            else {
                let snapshot = job.operation()
                result = .finished(snapshot)
            }
            lock.lock()
            if case .finished(var snapshot) = result, job.control.isCancelled {
                snapshot.cancelled = true; result = .finished(snapshot)
            }
            running.removeValue(forKey: job.id); finished += 1
            let next = pending.isEmpty || stopped ? nil : pending.removeFirst()
            if let next { admit(next) }
            lock.unlock()
            if let next { dispatch(next) }
            // Completion runs outside the admission lock and after the I/O slot is released.
            job.completion(result)
            WorkerTelemetry.shared.end("scan.worker", since: startedAt, cancelled: job.control.isCancelled)
        }
    }
    public func cancel(_ id: UUID) {
        lock.lock()
        if let index = pending.firstIndex(where: { $0.id == id }) {
            let job = pending.remove(at: index); cancelledBeforeStart += 1
            lock.unlock()
            job.control.cancel(); job.completion(.cancelledBeforeStart)
        } else {
            let control = running[id]
            // Linearize cancellation with slot release. No reverse control -> admission locking.
            control?.cancel(); lock.unlock()
        }
    }
    public func shutdown() {
        lock.lock(); stopped = true
        let cancelled = pending; pending.removeAll(); cancelledBeforeStart += cancelled.count
        for control in running.values { control.cancel() }
        lock.unlock()
        for job in cancelled { job.control.cancel(); job.completion(.cancelledBeforeStart) }
    }
    public func statistics() -> ScanAdmissionStatistics {
        lock.lock(); defer { lock.unlock() }
        return ScanAdmissionStatistics(limit: limit, capacity: capacity, active: running.count, queued: pending.count,
            peakActive: peakActive, started: started, finished: finished,
            cancelledBeforeStart: cancelledBeforeStart, rejected: rejected)
    }
}
