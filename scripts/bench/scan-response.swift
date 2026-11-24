import Foundation

private final class Counts: @unchecked Sendable {
    private let lock = NSLock(); private var began = 0; private var ended = 0; private var active = 0; private var peak = 0
    func begin() { lock.lock(); began += 1; active += 1; peak = max(peak, active); lock.unlock() }
    func endWork() { lock.lock(); active -= 1; lock.unlock() }
    func finish() -> Bool { lock.lock(); defer { lock.unlock() }; ended += 1; return ended == 32 }
    var peakOperations: Int { lock.lock(); defer { lock.unlock() }; return peak }
    var started: Int { lock.lock(); defer { lock.unlock() }; return began }
}
@main enum ScanResponseBenchmark {
    @MainActor static func main() async {
        let mode = CommandLine.arguments[1]
        let admission = mode == "detached" ? nil : ScanAdmission(limit: Int(mode)!)
        defer { admission?.shutdown() }
        let counts = Counts()
        var fixture = ScanSnapshot(rootPath: "/cpu")
        fixture.nodes.append(DiskNode(id: 0, parent: nil, path: "/cpu", name: "cpu", isDirectory: true))
        for id in 1...20000 { fixture.nodes.append(DiskNode(id: id, parent: 0, path: "/cpu/\(id).bin", name: "\(id).bin", logicalBytes: 1)) }
        let snapshot = fixture
        let start = ProcessInfo.processInfo.systemUptime
        let done = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                for _ in 0..<32 {
                    let operation: @Sendable () -> ScanSnapshot = {
                        counts.begin(); Thread.sleep(forTimeInterval: 0.05); counts.endWork()
                        return ScanSnapshot(rootPath: "/simulated-io")
                    }
                    let complete: @Sendable () -> Void = { if counts.finish() { continuation.resume() } }
                    if let admission { try! admission.submit(control: ScanControl(), operation: operation, completion: { _ in complete() }) }
                    else { Task.detached(priority: .utility) { _ = operation(); complete() } }
                }
            }
        }
        while counts.started == 0 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(2))
        let responseStart = ProcessInfo.processInfo.systemUptime
        let checksum = await Task.detached(priority: .userInitiated) {
            let filter = try! ScanFilter("*.bin")
            return filter.weights(in: snapshot, mode: .logical)[0]
        }.value
        let response = ProcessInfo.processInfo.systemUptime - responseStart
        precondition(checksum == 20000)
        await done.value
        print("{\"mode\":\"\(mode)\",\"response_seconds\":\(response),\"all_io_seconds\":\(ProcessInfo.processInfo.systemUptime-start),\"checksum\":\(checksum),\"peak_operations\":\(counts.peakOperations)}")
    }
}
