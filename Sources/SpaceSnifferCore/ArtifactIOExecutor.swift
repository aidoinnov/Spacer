import Foundation

public enum ArtifactIOError: LocalizedError {
    case busy
    public var errorDescription: String? { "파일 작업 대기열이 가득 찼습니다. 잠시 후 다시 시도하세요." }
}
/// Serial blocking-I/O execution preserves the former actor's operation order.
/// No Swift cooperative worker waits synchronously for this queue.
final class ArtifactIOExecutor: @unchecked Sendable {
    private let queue: DispatchQueue
    private let stage: String
    private let lock = NSLock()
    private let capacity: Int
    private var outstanding = 0
    init(capacity: Int = 64, label: String = "space-sniffer.artifact-io", stage: String = "artifact.io") {
        precondition(capacity >= 0); self.capacity = capacity; self.stage = stage
        queue = DispatchQueue(label: label, qos: .utility)
    }
    var outstandingCount: Int { lock.lock(); defer { lock.unlock() }; return outstanding }
    func run<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            enqueue(operation, continuation: continuation)
        }
    }
    private func enqueue<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value, continuation: CheckedContinuation<Value, any Error>) {
        lock.lock()
        guard outstanding < capacity + 1 else { lock.unlock(); continuation.resume(throwing: ArtifactIOError.busy); return }
        outstanding += 1; lock.unlock()
        let queuedAt = DispatchTime.now().uptimeNanoseconds; WorkerTelemetry.shared.note(stage, submitted: 1)
        queue.async { [self] in
            WorkerTelemetry.shared.record(stage); let started = WorkerTelemetry.shared.begin(stage, queuedAt: queuedAt)
            let result = Result(catching: operation)
            let failed: Bool; let cancelled: Bool
            if case .failure(let error) = result { cancelled = error is CancellationError; failed = !cancelled }
            else { cancelled = false; failed = false }
            WorkerTelemetry.shared.end(stage, since: started, cancelled: cancelled, failed: failed)
            lock.lock(); outstanding -= 1; lock.unlock()
            continuation.resume(with: result)
        }
    }
}
