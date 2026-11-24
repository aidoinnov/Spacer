import Foundation

/// Allocation investigation only. No pool implementation is linked into the app.
@main enum AllocationProbe {
    @inline(never) static func buildNodes(_ count: Int) -> NodeTable {
        var nodes = NodeTable()
        nodes.append(DiskNode(id: 0, parent: nil, path: "/allocation", name: "allocation", isDirectory: true))
        for id in 1...count {
            let name = "file-\(id).bin"
            nodes.append(DiskNode(id: id, parent: 0, path: "/allocation/" + name, name: name, logicalBytes: Int64(id)))
            nodes[0].children.append(id)
        }
        return nodes
    }
    @inline(never) static func scratch(_ count: Int, reuse: Bool) -> Int64 {
        var weights: [Int64] = []; var membership: [Bool] = []; var context: [UInt8] = []
        var checksum: Int64 = 0
        for pass in 0..<40 {
            if reuse {
                weights.removeAll(keepingCapacity: true); membership.removeAll(keepingCapacity: true); context.removeAll(keepingCapacity: true)
                weights.reserveCapacity(count); membership.reserveCapacity(count); context.reserveCapacity(count)
            } else {
                weights = []; membership = []; context = []
                weights.reserveCapacity(count); membership.reserveCapacity(count); context.reserveCapacity(count)
            }
            for id in 0..<count {
                weights.append(Int64(id + pass)); membership.append(id % 2 == 0); context.append(UInt8(id % 16))
            }
            checksum += weights[count - 1] + Int64(context[count - 1]) + (membership[0] ? 1 : 0)
        }
        return checksum
    }
    @inline(never) static func filter(_ count: Int, reuse: Bool) -> (Int64, Double) {
        var snapshot = ScanSnapshot(rootPath: "/allocation")
        snapshot.nodes = buildNodes(count); snapshot.tags = ["/allocation": 1]
        let filter = try! ScanFilter(":red")
        let scratch = reuse ? FilterScratch() : nil
        var checksum: Int64 = 0
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<40 {
            let included: [Bool]
            if let scratch { included = scratch.membership(filter: filter, snapshot: snapshot, showHidden: false, control: ScanControl())! }
            else { included = filter.membership(in: snapshot, showHidden: false)! }
            checksum += Int64(included.filter { $0 }.count)
        }
        return (checksum, ProcessInfo.processInfo.systemUptime - start)
    }
    static func main() {
        let mode = CommandLine.arguments.dropFirst().first ?? "nodes"
        let count = Int(CommandLine.arguments.dropFirst(2).first ?? "250000")!
        let start = ProcessInfo.processInfo.systemUptime
        var checksum: Int64 = 0; var computeSeconds: Double = 0
        if mode == "nodes" {
            var readers: [NodeTable] = []
            for _ in 0..<5 {
                var table = buildNodes(count)
                readers.append(table)
                if readers.count > 2 { readers.removeFirst() }
                table[1].logicalBytes = -1
                precondition(readers.last![1].logicalBytes == 1)
                checksum += table[count].logicalBytes
            }
        } else if mode.hasPrefix("filter-") {
            (checksum, computeSeconds) = filter(count, reuse: mode == "filter-reuse")
        } else { checksum = scratch(count, reuse: mode == "scratch-reuse") }
        print("{\"mode\":\"\(mode)\",\"count\":\(count),\"seconds\":\(ProcessInfo.processInfo.systemUptime-start),\"checksum\":\(checksum),\"compute_seconds\":\(computeSeconds)}")
        if ProcessInfo.processInfo.environment["SNIFFER_PROFILE_WAIT"] == "1" {
            fflush(stdout)
            _ = FileHandle.standardInput.readData(ofLength: 1)
        }
    }
}
