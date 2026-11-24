import Foundation
import Darwin
import CoreGraphics

@main enum FinalOptimizationProbe {
    static func seconds(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9 }
    static func interleaved(_ files: Int) -> ScanSnapshot {
        var s = ScanSnapshot(rootPath: "/fixture"); s.nodes.append(DiskNode(id: 0, parent: nil, path: "/fixture", name: "fixture", isDirectory: true))
        for branch in 0..<100 {
            let parent = s.nodes.count; let name = "branch-\(branch)"; let path = "/fixture/" + name
            s.nodes.append(DiskNode(id: parent, parent: 0, path: path, name: name, isDirectory: true)); s.nodes[0].children.append(parent)
            let count = files / 100 + (branch < files % 100 ? 1 : 0)
            for index in 0..<count {
                let id = s.nodes.count; let size = Int64(index % 1024)
                s.nodes.append(DiskNode(id: id, parent: parent, path: path + "/file-\(index).bin", name: "file-\(index).bin", logicalBytes: size, allocatedBytes: size == 0 ? 0 : 4096))
                s.nodes[parent].children.append(id)
            }
        }
        OptimizationFixture.aggregate(&s); s.fileCount = files; s.folderCount = 101; return s
    }
    static func navigation(mode: String, count: Int) -> [String: Any] {
        let snapshot = interleaved(count); let filter = try! ScanFilter("")
        let evaluation = ProjectionEvaluation(snapshot: snapshot, filter: filter, mode: .logical, showHidden: true, control: ScanControl())!
        let branches = snapshot.nodes[0].children; var lookup: [String: Int] = [:]
        var history = [snapshot.rootPath]; var checksum = 0; let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<20 {
            let path = snapshot.nodes[branches[99-index%10]].path; history.append(path)
            if mode == "legacy" {
                let value = LegacyNavigationState(snapshot: snapshot, previous: snapshot, included: evaluation.included, weights: evaluation.weights,
                    focusPath: path, selectionPath: nil, history: history, historyIndex: history.count-1, control: ScanControl())!
                checksum += value.focus + value.history.count
            } else {
                let value = NavigationState(snapshot: snapshot, previous: snapshot, included: evaluation.included, weights: evaluation.weights,
                    focusPath: path, selectionPath: nil, history: history, historyIndex: history.count-1, control: ScanControl(), lookup: lookup)!
                lookup = value.trackedLookup; checksum += value.focus + value.history.count
            }
        }
        return ["seconds":seconds(start),"checksum":checksum,"lookups":lookup.count,"operations":20]
    }
    static func geometry(mode: String, count: Int, scenario: String) -> [String: Any] {
        let snapshot = OptimizationFixture.metadata(files: count, shape: scenario == "branch" ? .balanced : .wide); let filter = try! ScanFilter("")
        let root = scenario == "branch" ? 1 : 0
        let weights = filter.weights(in: snapshot, mode: .logical); let source = GeometrySource(snapshot: snapshot, weights: weights)
        let cache = GeometrySession(); var checksum = 0.0; let start = DispatchTime.now().uptimeNanoseconds
        for step in 0..<20 {
            let width = scenario == "alternating" || scenario == "branch" ? 1400 + (step % 2) * 100 : 1400 + step
            let bounds = CGRect(x: 0, y: 0, width: width, height: 900)
            let result = mode == "legacy" ? LegacyTreemap.tiles(snapshot: snapshot, weights: weights, root: root, depth: 2, selected: nil, in: bounds, control: ScanControl())! : cache.tiles(source: source, root: root, depth: 2, selected: nil, in: bounds, control: ScanControl())!
            checksum += result.reduce(0) { $0 + Double($1.id) + $1.rect.minX + $1.rect.minY + $1.rect.width + $1.rect.height }
        }
        let duration = seconds(start); let stats = cache.statistics(); cache.reset()
        return ["seconds":duration,"checksum":checksum,"sorts":stats.sorts,"sort_hits":stats.sortHits,"rect_hits":stats.rectHits,"sort_slots":stats.retainedSortItems,"rect_tiles":stats.retainedTiles,"after_reset":cache.statistics().retainedTiles]
    }
    static func delta(mode: String, count: Int, scenario: String) -> [String: Any] {
        var snapshot = OptimizationFixture.metadata(files: count)
        let filter = try! ScanFilter(":red;*.bin;>32kb"); var source = ProjectionSource(snapshot)
        var evaluation = ProjectionEvaluation(snapshot: snapshot, filter: filter, mode: .logical, showHidden: false, control: ScanControl())!
        var secondsTotal = 0.0; var checksum: Int64 = 0; var incremental = 0; var full = 0
        var readers: [(ScanSnapshot, ProjectionEvaluation)] = []
        for pass in 0..<12 {
            var next = snapshot
            let first = 101 + min(15000, count/2)
            let ids = scenario == "dense" ? Array(101..<next.nodes.count) : scenario == "independent" ? [first, first+1024,first+2048,first+3072].filter { $0 < next.nodes.count } : scenario == "branch" ? Array(first..<min(first+16,next.nodes.count)) : [first]
            for id in ids where !next.nodes[id].isDirectory {
                next.nodes[id].logicalBytes = pass % 2 == 0 ? 70000 : 0; next.nodes[id].allocatedBytes = pass % 2 == 0 ? 73728 : 0
                next.nodes[id].modified = next.nodes[id].modified.addingTimeInterval(1)
            }
            if scenario == "rename" { next.nodes[first].name = "changed-\(pass).bin"; next.nodes[first].path = next.nodes[next.nodes[first].parent!].path + "/" + next.nodes[first].name }
            OptimizationFixture.aggregate(&next); let result = ProjectionSource(next)
            let start = DispatchTime.now().uptimeNanoseconds
            let value: ProjectionEvaluation
            if mode != "legacy", let payload = ProjectionDelta(baseline: source, result: result, control: ScanControl()),
               let updated = payload.apply(previous: evaluation, baseline: source, result: result, filter: filter, mode: .logical, showHidden: false, control: ScanControl()) {
                value = updated; incremental += 1
            } else { value = ProjectionEvaluation(snapshot: next, filter: filter, mode: .logical, showHidden: false, control: ScanControl())!; full += 1 }
            secondsTotal += seconds(start)
            let oracle = ProjectionEvaluation(snapshot: next, filter: filter, mode: .logical, showHidden: false, control: ScanControl())!
            precondition(value.included == oracle.included && value.weights == oracle.weights)
            checksum += value.weights.first ?? 0
            readers.append((snapshot,evaluation)); if readers.count > 2 { readers.removeFirst() }
            source = result; snapshot = next; evaluation = value
        }
        return ["seconds":secondsTotal,"checksum":checksum,"incremental":incremental,"full":full,"readers":readers.count,"iterations":12]
    }
    @inline(never) static func poolInput(_ base: [DiskNode], pass: Int) -> [DiskNode] {
        let root = "/prototype/g\(pass)"
        var values = base.map { old in
            var node = old; node.name = old.id == 0 ? "g\(pass)" : "g\(pass)-" + old.name; node.path = old.id == 0 ? root : root + "/" + node.name
            if !node.isDirectory { node.logicalBytes += Int64(pass) }
            node.modified = Date(timeIntervalSince1970: 1_700_000_000 + Double(pass)); node.created = node.modified; node.accessed = node.modified
            node.fileIdentity = "\(pass):\(node.id)"; node.issue = pass % 2 == 0 ? "synthetic issue" : nil; node.nativeFlags = UInt8(pass)
            return node
        }
        values[0].logicalBytes = values.dropFirst().reduce(0) { $0 + $1.logicalBytes }
        values[0].allocatedBytes = values.dropFirst().reduce(0) { $0 + $1.allocatedBytes }
        return values
    }
    @inline(never) static func pools(mode: String, count: Int) -> [String: Any] {
        let base = Array(OptimizationFixture.metadata(files: count, shape: .wide).nodes)
        let kind = PoolCandidate.Kind(rawValue: mode) ?? .current; let pool = PoolCandidate(kind)
        let scratch = mode == "fresh" ? nil : FilterScratch()
        let filter = try! ScanFilter(":red;*.bin")
        var readers: [(CandidateReader,[DiskNode])] = []; var snapshots: [ScanSnapshot] = []
        var build = 0.0; var adapt = 0.0; var filtering = 0.0; var checksum: Int64 = 0
        for pass in 0..<8 {
            let input = poolInput(base, pass: pass)
            var start = DispatchTime.now().uptimeNanoseconds; let reader = pool.build(input); build += seconds(start)
            start = DispatchTime.now().uptimeNanoseconds; let table = reader.adapted(); adapt += seconds(start)
            var snapshot = ScanSnapshot(rootPath: input[0].path); snapshot.nodes = table; snapshot.tags[snapshot.rootPath] = 1
            snapshot.fileCount = input.count - 1; snapshot.folderCount = 1
            start = DispatchTime.now().uptimeNanoseconds
            let evaluation = ProjectionEvaluation(snapshot: snapshot, filter: filter, mode: .logical, showHidden: false, control: ScanControl(), scratch: scratch)!
            filtering += seconds(start); checksum += evaluation.weights[0]
            precondition(reader.materialized() == input)
            readers.append((reader,input)); snapshots.append(snapshot)
            if readers.count > 2 { readers.removeFirst(); snapshots.removeFirst() }
            for (frozen, expected) in readers { precondition(frozen.materialized() == expected) }
        }
        let stats = pool.statistics(); pool.evict(); let scratchStats = ScratchResources.statistics()
        return ["seconds":build+adapt+filtering,"build_seconds":build,"adapter_seconds":adapt,"filter_seconds":filtering,"checksum":checksum,
            "hits":stats.hits,"misses":stats.misses,"busy_exclusions":stats.busyExclusions,"retained_charge":stats.retainedCharge,
            "evicted_charge":pool.statistics().evictedCharge,"after_evict":pool.statistics().retainedCharge,"frozen_generations":readers.count,
            "scratch_capacity":scratch?.retainedBytes ?? 0,"scratch_hits":scratchStats.hits,"scratch_misses":scratchStats.misses]
    }
    static func overhead() -> [String: Any] {
        let telemetry = WorkerTelemetry(); let rounds = 100_000
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<rounds { telemetry.observe("calibration", nanoseconds: 1) }
        return ["seconds":seconds(start),"operations":rounds,"samples":telemetry.snapshot()["calibration"]!.recentNanoseconds.count]
    }
    @inline(never) static func scratchFiltering(mode: String, count: Int) -> [String: Any] {
        let snapshot = OptimizationFixture.metadata(files: count); let filter = try! ScanFilter(":red")
        let scratch = mode == "current" ? FilterScratch() : nil; var checksum: Int64 = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<40 {
            let included = scratch?.membership(filter: filter, snapshot: snapshot, showHidden: false, control: ScanControl()) ?? filter.membership(in: snapshot, showHidden: false)!
            checksum += Int64(included.filter { $0 }.count)
        }
        return ["seconds":seconds(start),"checksum":checksum,"iterations":40,"scratch_capacity":scratch?.retainedBytes ?? 0]
    }
    @inline(never) static func arrayCOW(_ count: Int) -> [String: Any] {
        var writer = Array(repeating: Int64(1), count: count); let frozen = writer
        let start = DispatchTime.now().uptimeNanoseconds; writer[count/2] = 2; let duration = seconds(start)
        let separate = frozen.withUnsafeBufferPointer { old in writer.withUnsafeBufferPointer { new in old.baseAddress != new.baseAddress } }
        let before = frozen.reduce(Int64(0),+); let after = writer.reduce(Int64(0),+)
        precondition(separate && before == count && after == count+1)
        return ["seconds":duration,"distinct_live_buffers":separate,"old_sum":before,"new_sum":after,"element_payload_bytes_per_array":count*MemoryLayout<Int64>.stride]
    }
    // Distinct post-call markers prevent WMO identical-function folding and
    // tail-call removal from merging phase allocation stacks.
    @inline(never) static func firstScan(_ root: URL) -> ScanSnapshot { let s = DiskScanner.scan(root); WorkerTelemetry.shared.record("profile.fs.first"); return s }
    @inline(never) static func repeatedScan(_ root: URL) -> ScanSnapshot { let s = DiskScanner.scan(root); WorkerTelemetry.shared.record("profile.fs.repeat"); return s }
    @inline(never) static func addedScan(_ root: URL) -> ScanSnapshot { let s = DiskScanner.scan(root); WorkerTelemetry.shared.record("profile.fs.add"); return s }
    @inline(never) static func deletedScan(_ root: URL) -> ScanSnapshot { let s = DiskScanner.scan(root); WorkerTelemetry.shared.record("profile.fs.delete"); return s }
    @inline(never) static func renamedScan(_ root: URL) -> ScanSnapshot { let s = DiskScanner.scan(root); WorkerTelemetry.shared.record("profile.fs.rename"); return s }
    @inline(never) static func profiledFilter(_ snapshot: ScanSnapshot) -> [Int64] { try! ScanFilter("*.bin;>1kb").weights(in: snapshot, mode: .logical) }
    static func filesystem() throws -> [String: Any] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-profile-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try OptimizationFixture.disk(at: root, branches: 8)
        var rows: [[String: Any]] = []; var readers: [ScanSnapshot] = []
        func record(_ name: String, _ scan: () -> ScanSnapshot) {
            let start = DispatchTime.now().uptimeNanoseconds; let snapshot = scan()
            rows.append(["phase":name,"seconds":seconds(start),"nodes":snapshot.nodes.count,"bytes":snapshot.nodes[0].logicalBytes]); readers.append(snapshot)
        }
        record("first") { firstScan(root) }; record("repeat") { repeatedScan(root) }
        let added = root.appendingPathComponent("branch-0/added.bin"); try Data(repeating: 1, count: 1025).write(to: added)
        record("add") { addedScan(root) }; try FileManager.default.removeItem(at: added)
        record("delete") { deletedScan(root) }
        try FileManager.default.moveItem(at: root.appendingPathComponent("branch-1/café.txt"), to: root.appendingPathComponent("branch-1/renamed.txt"))
        record("rename") { renamedScan(root) }; let start = DispatchTime.now().uptimeNanoseconds
        let weights = profiledFilter(readers.last!); rows.append(["phase":"filter","seconds":seconds(start),"bytes":weights[0]])
        precondition(readers[0].nodes.map(\.path) == readers[1].nodes.map(\.path))
        return ["phases":rows,"frozen_readers":readers.count]
    }
    static func fixtureMatrix(_ path: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        for (shape, count) in [(OptimizationFixture.Shape.small,64),(.wide,25000),(.deep,2000),(.balanced,250000),(.edges,64)] {
            let snapshot = OptimizationFixture.metadata(files: count, shape: shape); _ = try snapshot.validated()
            let url = root.appendingPathComponent(shape.rawValue + ".sns"); try ArtifactTransfer.save(snapshot, to: url)
            rows.append(["shape":shape.rawValue,"files":count,"nodes":snapshot.nodes.count,"path":url.path,"logical":snapshot.nodes[0].logicalBytes])
        }
        return ["seed":String(OptimizationFixture.seed),"fixtures":rows]
    }
    static func reorder(mode: String, count: Int, scenario: String) -> [String: Any] {
        var values = (0..<count).map { ($0,Double(($0 * 7919) % 100001 + 1)) }
        func less(_ a: (Int,Double), _ b: (Int,Double)) -> Bool { a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }
        var ordered = values.sorted(by: less); var duration = 0.0; var checksum = 0
        for pass in 0..<20 {
            let amount = scenario == "dense" ? count : scenario == "branch" ? 16 : 1
            let changed = Set((0..<amount).map { ($0+pass*17)%count })
            for id in changed { values[id].1 = pass % 2 == 0 ? 100003 : 0.25 }
            let start = DispatchTime.now().uptimeNanoseconds
            if mode == "legacy" { ordered = values.sorted(by: less) }
            else {
                ordered.removeAll { changed.contains($0.0) }
                for id in changed {
                    let value = values[id]; var lower = 0; var upper = ordered.count
                    while lower < upper { let middle = (lower+upper)/2; if less(ordered[middle],value) { lower=middle+1 } else { upper=middle } }
                    ordered.insert(value, at: lower)
                }
            }
            duration += seconds(start)
            let oracle = values.sorted(by: less); precondition(ordered.map(\.0)==oracle.map(\.0))
            checksum += ordered.first!.0 + ordered.last!.0
        }
        return ["seconds":duration,"checksum":checksum,"iterations":20,"scope":"isolated reinsert candidate; supplied exact changed IDs; no provenance/geometry included; dense fallback required"]
    }
    static func main() throws {
        let a = CommandLine.arguments; let scenario = a.count > 4 ? a[4] : "default"; let mode = a.count > 2 ? a[2] : "current"; let count = a.count > 3 ? Int(a[3])! : 250000
        var result: [String: Any]
        switch a[1] {
        case "navigation": result = navigation(mode: mode, count: count)
        case "geometry": result = geometry(mode: mode, count: count, scenario: scenario)
        case "delta": result = delta(mode: mode, count: count, scenario: scenario)
        case "pools": result = pools(mode: mode, count: count)
        case "telemetry": result = overhead()
        case "scratch-filter": result = scratchFiltering(mode: mode, count: count)
        case "cow": result = arrayCOW(count)
        case "filesystem": result = try filesystem()
        case "fixture-matrix": result = try fixtureMatrix(mode)
        case "reorder": result = reorder(mode: mode, count: count, scenario: scenario)
        case "fixture": let source = interleaved(count); try ArtifactTransfer.save(source, to: URL(fileURLWithPath: mode)); result = ["nodes":source.nodes.count,"files":source.fileCount,"bytes":source.nodes[0].logicalBytes]
        default: fatalError("unknown probe")
        }
        result["probe"] = a[1]; result["mode"] = mode; result["count"] = count; result["scenario"] = scenario
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
        if ProcessInfo.processInfo.environment["SNIFFER_PROFILE_WAIT"] == "1" { fflush(stdout); _ = FileHandle.standardInput.readData(ofLength: 1) }
    }
}
