import Foundation
import SpaceSnifferScanEngine

/// macOS composition only. Synchronization, cancellation, permits and queue
/// lifecycle have one implementation in the independent shared engine package.
final class DirectoryReadPool: @unchecked Sendable {
    static let shared = DirectoryReadPool(workers: MacScanResources.readerWorkers, capacity: MacScanResources.queueCapacity)
    private let pool: DirectoryWorkerPool<DirectoryReadOutput>
    init(workers: Int, capacity: Int, budget: DirectoryIOBudget = MacScanResources.directoryIO) {
        pool = DirectoryWorkerPool(workers: workers, capacity: capacity, budget: budget,
            cancelledOutput: { DirectoryReadOutput(value: .cancelled, statistics: ScanIOStatistics()) },
            configureWorker: { thread, _ in
                // NSCondition does not donate caller QoS to the producer.
                thread.qualityOfService = .userInitiated
            })
    }
    func submit(control: ScanControl, operation: @escaping @Sendable () -> DirectoryReadOutput) -> DirectoryReadTicket? {
        pool.submit(control: control, operation: operation)
    }
    func submit(reader: MacDirectoryBatchReader, path: String, control: ScanControl) -> DirectoryReadTicket? {
        pool.submit(reader: reader, path: path, control: control)
    }
    func cancelQueued(control: ScanControl) { pool.cancelQueued(control: control) }
    func shutdown() { pool.shutdown() }
    var observation: (active: Int, queued: Int, live: Int) { pool.observation }
}
