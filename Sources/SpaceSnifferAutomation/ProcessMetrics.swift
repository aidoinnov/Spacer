import Foundation
import Darwin
import SpaceSnifferCore

public enum ProcessMetrics {
    private static let sampler = MetricsSampler()
    public static func readAsync() async throws -> JSONValue { try await sampler.read() }
    private static func threads() -> [String: JSONValue] {
        var list: thread_act_array_t?; var count: mach_msg_type_number_t = 0
        let code = task_threads(mach_task_self_, &list, &count)
        guard code == KERN_SUCCESS, let list else { return ["thread_count": .null, "mach_threads_status": .int(Int(code))] }
        defer {
            for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[index]) }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var samples: [JSONValue] = []
        for index in 0..<min(64, Int(count)) {
            var basic = thread_basic_info_data_t(); var size = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &basic) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { thread_info(list[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &size) } }
            var identifier = thread_identifier_info_data_t(); var idSize = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<integer_t>.size)
            let idStatus = withUnsafeMutablePointer(to: &identifier) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(idSize)) { thread_info(list[index], thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &idSize) } }
            if status == KERN_SUCCESS {
                samples.append(.object(["id": idStatus == KERN_SUCCESS ? .string(String(identifier.thread_id)) : .null,
                    "run_state": .int(Int(basic.run_state)), "flags": .int(Int(basic.flags))]))
            }
        }
        return ["thread_count": .int(Int(count)), "mach_threads_status": .int(Int(code)), "sampled_thread_states": .array(samples)]
    }
    public static func read() -> JSONValue { read(queuedAt: nil) }
    fileprivate static func read(queuedAt: UInt64?) -> JSONValue {
        WorkerTelemetry.shared.record("metrics.sample")
        let started = WorkerTelemetry.shared.begin("metrics.sample", queuedAt: queuedAt)
        defer { WorkerTelemetry.shared.end("metrics.sample", since: started) }
        var basic = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let basicCode = withUnsafeMutablePointer(to: &basic) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        var vm = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmCode = withUnsafeMutablePointer(to: &vm) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount) } }
        var usage = rusage(); let usageCode = getrusage(RUSAGE_SELF, &usage)
        var thread: UInt64 = 0; pthread_threadid_np(nil, &thread)
        var values = ["pid": JSONValue.int(Int(getpid())), "measured_at": .date(Date()),
            "resident_bytes": basicCode == KERN_SUCCESS ? .integer(Int64(basic.resident_size)) : .null,
            "virtual_bytes": basicCode == KERN_SUCCESS ? .integer(Int64(basic.virtual_size)) : .null,
            "physical_footprint_bytes": vmCode == KERN_SUCCESS ? .integer(Int64(vm.phys_footprint)) : .null,
            "cpu_user_seconds": usageCode == 0 ? .number(Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec)/1e6) : .null,
            "cpu_system_seconds": usageCode == 0 ? .number(Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec)/1e6) : .null,
            "mach_basic_status": .int(Int(basicCode)), "mach_vm_status": .int(Int(vmCode)),
            "sampling_thread_id": .string(String(thread)), "sampling_on_main_thread": .bool(Thread.isMainThread)]
        values.merge(threads()) { _, new in new }; return .object(values)
    }
}

private final class MetricsSampler: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "space-sniffer.metrics", qos: .utility)
    private var outstanding = 0
    func read() async throws -> JSONValue {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard outstanding < 33 else { lock.unlock(); continuation.resume(throwing: ControlError("busy", "Metrics sampling queue is full")); return }
            outstanding += 1; lock.unlock()
            let queuedAt = DispatchTime.now().uptimeNanoseconds
            WorkerTelemetry.shared.note("metrics.sample", submitted: 1)
            queue.async { [self] in
                let result = ProcessMetrics.read(queuedAt: queuedAt)
                lock.lock(); outstanding -= 1; lock.unlock()
                continuation.resume(returning: result)
            }
        }
    }
}
