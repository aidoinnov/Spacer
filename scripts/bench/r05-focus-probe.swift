import Foundation
import Darwin

@main enum R05FocusProbe {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static func stamp() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func seconds(_ start: UInt64) -> Double { Double(stamp() &- start) / 1e9 }
    static func metrics() -> [String: Any] {
        var basic = mach_task_basic_info()
        var n = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let bc = withUnsafeMutablePointer(to: &basic) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &n) } }
        var vm = task_vm_info_data_t()
        var vn = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vc = withUnsafeMutablePointer(to: &vm) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(vn)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vn) } }
        var ru = rusage(); let rc = getrusage(RUSAGE_SELF, &ru)
        return ["resident_bytes": bc == KERN_SUCCESS ? Int64(basic.resident_size) : -1,
            "physical_footprint_bytes": vc == KERN_SUCCESS ? Int64(vm.phys_footprint) : -1,
            "peak_rss_bytes": rc == 0 ? ru.ru_maxrss : -1,
            "cpu_user_seconds": Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6,
            "cpu_system_seconds": Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6]
    }
    static func fixture(_ files: Int) -> ScanSnapshot {
        var s = ScanSnapshot(rootPath: "/fixture")
        s.started = now; s.finished = now
        s.nodes.append(DiskNode(id: 0, parent: nil, path: s.rootPath, name: "fixture", isDirectory: true))
        for name in ["small", "large", "other"] {
            let id = s.nodes.count
            s.nodes.append(DiskNode(id: id, parent: 0, path: s.rootPath + "/" + name, name: name, isDirectory: true))
            s.nodes[0].children.append(id)
        }
        var parents: [[Int]] = []
        for branch in 1...3 {
            var group: [Int] = []
            for i in 0..<8 {
                let id = s.nodes.count; let name = i == 7 ? "blocked" : "group-\(i)"
                var node = DiskNode(id: id, parent: branch, path: s.nodes[branch].path + "/" + name, name: name, isDirectory: true)
                if i == 5 { node.nativeAttributes = 2 }
                s.nodes.append(node); s.nodes[branch].children.append(id); group.append(id)
                if i == 3 { s.tags[node.path] = 1 }
            }
            parents.append(group)
        }
        s.tags[s.rootPath] = 2; s.tags[s.nodes[1].path] = 1; s.tags[s.nodes[2].path] = 4
        var random: UInt64 = 0x534e4946464552
        for index in 0..<files {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            let branch = index % 100 == 0 ? 0 : index % 100 < 51 ? 1 : 2
            let parent = parents[branch][index % 8]
            let id = s.nodes.count
            let name = "\(index)-" + ["a.bin", "UPPER.BIN", "café.txt", "cafe\u{301}.bin", "한글.bin", "line\n.bin"][index % 6]
            let size = index % 17 == 0 ? 0 : Int64(random % 65536)
            var file = DiskNode(id: id, parent: parent, path: s.nodes[parent].path + "/" + name, name: name,
                logicalBytes: size, allocatedBytes: size == 0 ? 0 : ((size + 4095) / 4096) * 4096,
                modified: now.addingTimeInterval(-[500, 1000, 1999.5, 2001][index % 4]))
            file.created = now.addingTimeInterval(-86400); file.accessed = now.addingTimeInterval(-100)
            if index % 23 == 0 { file.nativeAttributes = 2 }
            s.nodes.append(file); s.nodes[parent].children.append(id)
        }
        for id in stride(from: s.nodes.count - 1, through: 1, by: -1) {
            if let parent = s.nodes[id].parent { s.nodes[parent].logicalBytes += s.nodes[id].logicalBytes; s.nodes[parent].allocatedBytes += s.nodes[id].allocatedBytes }
        }
        for id in 0..<28 {
            s.nodes[id].modified = now.addingTimeInterval(-1000)
            s.nodes[id].created = now.addingTimeInterval(-86400)
            s.nodes[id].accessed = now.addingTimeInterval(-100)
        }
        s.fileCount = files; s.folderCount = 28
        return s
    }
    static func config(_ name: String) -> (String, Bool) {
        switch name {
        case "empty": return ("", true)
        case "mask": return ("*.bin", true)
        case "tags": return (":red;*.bin", false)
        case "folders": return ("\\group-3;*.bin", false)
        case "time": return ("*.bin;modified>500s;modified<2000s", false)
        default: return (":tag:red+green;\\group-3;|\\blocked;*.bin;>1kb", false)
        }
    }
    static func checksum(_ included: [Bool], _ weights: [Int64]) -> UInt64 {
        var sum: UInt64 = 0xcbf29ce484222325
        for id in weights.indices { sum = (sum ^ UInt64(bitPattern: weights[id]) ^ UInt64(id &* 2 + (included[id] ? 1 : 0))) &* 0x100000001b3 }
        return sum
    }
    static func subtree(_ snapshot: ScanSnapshot, root: Int) -> [Int] {
        var ids: [Int] = []; var stack = [root]
        while let id = stack.popLast() { ids.append(id); stack.append(contentsOf: snapshot.nodes[id].children.reversed()) }
        return ids
    }
    @inline(never) static func execute(_ s: ScanSnapshot, mode: String, focus: Int, expression: String, hidden: Bool) -> [String: Any] {
        let filter = try! ScanFilter(expression); let control = ScanControl()
        let before = metrics(); let start = stamp()
        var ready = 0.0; var frozenIncluded: [Bool]?; var frozenWeights: [Int64]?; var atFocus: [String: Any] = [:]
        func publish(_ included: [Bool], _ weights: [Int64]) {
            ready = seconds(start); frozenIncluded = included; frozenWeights = weights
            atFocus = metrics()
        }
        let value: R05Evaluation
        if mode == "focus" {
            value = filter.r05FocusFirst(in: s, mode: .logical, showHidden: hidden, focus: focus, now: now, control: control, onFocus: publish)!
        } else if mode == "fused" {
            value = filter.r05Fused(in: s, mode: .logical, showHidden: hidden, now: now, control: control)!
            publish(value.included, value.weights)
        } else {
            let included = filter.membership(in: s, showHidden: hidden, control: control, now: now)!
            let weights = filter.weights(in: s, mode: .logical, included: included, control: control)
            value = R05Evaluation(included: included, weights: weights, focusIDs: [], ancestorContexts: 0)
            publish(included, weights)
        }
        let total = seconds(start); let after = metrics()
        // Oracle, full-array hashes and reader validation are outside timed scope.
        let oracleIncluded = filter.membership(in: s, showHidden: hidden, now: now)!
        let oracleWeights = filter.weights(in: s, mode: .logical, included: oracleIncluded)
        precondition(value.included == oracleIncluded && value.weights == oracleWeights)
        let ids = subtree(s, root: focus)
        precondition(ids.allSatisfy { frozenIncluded![$0] == oracleIncluded[$0] && frozenWeights![$0] == oracleWeights[$0] })
        if mode == "focus" && focus != 0 {
            var scope = Array(repeating: false, count: s.nodes.count)
            for id in ids { scope[id] = true }
            for id in scope.indices where !scope[id] {
                precondition(frozenWeights![id] == 0 && frozenIncluded![id] == (filter.isEmpty && hidden))
            }
        }
        let distinctWeights = frozenWeights!.withUnsafeBufferPointer { old in value.weights.withUnsafeBufferPointer { new in old.baseAddress != new.baseAddress } }
        let distinctIncluded = frozenIncluded!.withUnsafeBufferPointer { old in value.included.withUnsafeBufferPointer { new in old.baseAddress != new.baseAddress } }
        if mode == "focus" && focus != 0 { precondition(distinctWeights) }
        return ["mode": mode, "nodes": s.nodes.count, "focus": focus, "focus_nodes": ids.count,
            "expression": expression, "show_hidden": hidden, "focus_ready_seconds": ready, "total_seconds": total,
            "before": before, "at_focus": atFocus, "after": after, "after_oracle": metrics(),
            "checksum": String(checksum(value.included, value.weights)),
            "frozen_checksum": String(checksum(frozenIncluded!, frozenWeights!)),
            "weight_buffers_distinct": distinctWeights, "membership_buffers_distinct": distinctIncluded,
            "ancestor_contexts": value.ancestorContexts, "oracle_equal": true, "frozen_scope_equal": true]
    }
    static func verify() -> [String: Any] {
        var comparisons = 0; var cancellationChecks = 0
        for count in [0, 1, 97, 2048] {
            var s = fixture(count)
            if count == 97 { s.nodes[0].nativeType = 1 }
            for name in ["empty", "mask", "tags", "folders", "time", "mixed"] {
                let (expression, hidden) = config(name); let filter = try! ScanFilter(expression)
                for mode in SizeMode.allCases { for visible in [hidden, !hidden] {
                    let expected = filter.membership(in: s, showHidden: visible, now: now)!
                    let weights = filter.weights(in: s, mode: mode, included: expected)
                    for focus in [0, 1, 2, 3, s.nodes.count - 1] {
                        var frozen: ([Bool], [Int64])?
                        let value = filter.r05FocusFirst(in: s, mode: mode, showHidden: visible, focus: focus, now: now, control: ScanControl()) { frozen = ($0, $1) }!
                        precondition(value.included == expected && value.weights == weights)
                        precondition(value.focusIDs.allSatisfy { frozen!.0[$0] == expected[$0] && frozen!.1[$0] == weights[$0] })
                        comparisons += 1
                    }
                    let fused = filter.r05Fused(in: s, mode: mode, showHidden: visible, now: now, control: ScanControl())!
                    precondition(fused.included == expected && fused.weights == weights); comparisons += 1
                } }
            }
            let filter = try! ScanFilter(":red;*.bin")
            let stopped = ScanControl(); stopped.cancel()
            precondition(filter.r05FocusFirst(in: s, mode: .logical, showHidden: false, focus: 1, now: now, control: stopped) { _,_ in preconditionFailure() } == nil)
            let mid = ScanControl(); var frozen: ([Bool], [Int64])?
            let cancelled = filter.r05FocusFirst(in: s, mode: .logical, showHidden: false, focus: 1, now: now, control: mid) { frozen = ($0,$1); mid.cancel() }
            precondition(cancelled == nil && frozen != nil); cancellationChecks += 2
        }
        return ["comparisons": comparisons, "cancellation_checks": cancellationChecks, "passed": true]
    }
    static func main() throws {
        let a = CommandLine.arguments
        let result: [String: Any]
        if a[1] == "verify" { result = verify() }
        else {
            let count = Int(a[2])!; let shape = a[3]; let (text, hidden) = config(a[4]); let s = fixture(count)
            let focus = shape == "root" ? 0 : shape == "large" ? 2 : 1
            result = execute(s, mode: a[1], focus: focus, expression: text, hidden: hidden).merging(["files": count,"scenario": shape,"filter_case": a[4]]) { _,new in new }
        }
        let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }
}
