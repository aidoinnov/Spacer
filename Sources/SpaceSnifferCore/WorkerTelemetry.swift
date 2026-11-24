import Foundation
import Darwin

public struct WorkerSample: Codable, Sendable {
    public var runs = 0
    public var mainThreadRuns = 0
    public var submitted = 0
    public var started = 0
    public var completed = 0
    public var cancelled = 0
    public var failed = 0
    public var coalesced = 0
    public var staleDrops = 0
    public var active = 0
    public var peakActive = 0
    public var timedCalls = 0
    public var totalNanoseconds: UInt64 = 0
    public var maximumNanoseconds: UInt64 = 0
    public var recentNanoseconds: [UInt64] = []
    public var queueSamples = 0
    public var queueNanoseconds: UInt64 = 0
    public var maximumQueueNanoseconds: UInt64 = 0
    public var threadIDs: [UInt64] = []
}
/// Bounded diagnostics: stage names and counters only; no file paths or user content.
public final class WorkerTelemetry: @unchecked Sendable {
    public static let shared = WorkerTelemetry()
    private let lock = NSLock()
    private var stages: [String: WorkerSample] = [:]
    private let stageLimit: Int
    private let sampleLimit: Int
    init(stageLimit: Int = 128, sampleLimit: Int = 256) { precondition(stageLimit > 0 && sampleLimit > 0); self.stageLimit = stageLimit; self.sampleLimit = sampleLimit }
    private func key(_ name: String) -> String {
        guard name.utf8.count <= 64, name.utf8.allSatisfy({ $0 >= 45 && $0 <= 122 && $0 != 47 && $0 != 92 }) else { return "other" }
        return stages[name] != nil || stages.count < stageLimit - 1 ? name : "other"
    }
    public func record(_ stage: String) {
        lock.lock(); defer { lock.unlock() }
        let stage = key(stage)
        var sample = stages[stage] ?? WorkerSample(); sample.runs += 1
        if Thread.isMainThread { sample.mainThreadRuns += 1 }
        stages[stage] = sample
    }
    public func note(_ stage: String, submitted: Int = 0, coalesced: Int = 0, cancelled: Int = 0, stale: Int = 0) {
        lock.lock(); defer { lock.unlock() }; let stage = key(stage)
        var value = stages[stage] ?? WorkerSample()
        value.submitted += submitted; value.coalesced += coalesced; value.cancelled += cancelled; value.staleDrops += stale
        stages[stage] = value
    }
    public func begin(_ stage: String, queuedAt: UInt64? = nil) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        var thread: UInt64 = 0; pthread_threadid_np(nil, &thread)
        lock.lock(); defer { lock.unlock() }; let stage = key(stage)
        var value = stages[stage] ?? WorkerSample(); value.started += 1; value.active += 1; value.peakActive = max(value.peakActive, value.active)
        if let queuedAt { let duration = now &- queuedAt; value.queueSamples += 1; value.queueNanoseconds &+= duration; value.maximumQueueNanoseconds = max(value.maximumQueueNanoseconds, duration) }
        if !value.threadIDs.contains(thread), value.threadIDs.count < 32 { value.threadIDs.append(thread) }
        stages[stage] = value; return now
    }
    public func end(_ stage: String, since start: UInt64, cancelled: Bool = false, failed: Bool = false) {
        let duration = DispatchTime.now().uptimeNanoseconds &- start
        lock.lock(); defer { lock.unlock() }; let stage = key(stage)
        // Mutate the dictionary value through its inout accessor. Copying it to
        // a local first would COW the recent-sample array on every observation.
        finish(&stages[stage, default: WorkerSample()], duration: duration, cancelled: cancelled, failed: failed)
    }
    private func finish(_ value: inout WorkerSample, duration: UInt64, cancelled: Bool, failed: Bool) {
        value.active = max(0, value.active - 1)
        if cancelled { value.cancelled += 1 } else if failed { value.failed += 1 } else { value.completed += 1 }
        append(duration, to: &value)
    }
    public func observe(_ stage: String, nanoseconds: UInt64) {
        lock.lock(); defer { lock.unlock() }; let stage = key(stage)
        append(nanoseconds, to: &stages[stage, default: WorkerSample()])
    }
    private func append(_ duration: UInt64, to value: inout WorkerSample) {
        value.timedCalls += 1; value.totalNanoseconds &+= duration; value.maximumNanoseconds = max(value.maximumNanoseconds, duration)
        if value.recentNanoseconds.count == sampleLimit { value.recentNanoseconds.removeFirst() }
        value.recentNanoseconds.append(duration)
    }
    public func measure<T>(_ stage: String, operation: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer { observe(stage, nanoseconds: DispatchTime.now().uptimeNanoseconds &- start) }
        return try operation()
    }
    public func snapshot() -> [String: WorkerSample] { lock.lock(); defer { lock.unlock() }; return stages }
}
