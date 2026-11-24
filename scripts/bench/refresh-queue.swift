import Foundation

protocol QueueProbe {
    init()
    mutating func insert(_ path: String)
    mutating func popFirst() -> String?
    mutating func removeAll()
    var slots: Int { get }
}
extension RefreshQueue: QueueProbe { var slots: Int { indexSlots } }
extension LegacyRefreshQueue: QueueProbe { var slots: Int { 0 } }

@main enum RefreshProbe {
    static func run<Q: QueueProbe>(_ type: Q.Type, scenario: String, n: Int) -> [String: Any] {
        let paths = (0..<n).map { "/fixture/branch-\($0)/leaf" }
        var queue = Q(); var hash: UInt64 = 14695981039346656037; var pops = 0; var peakSlots = 0
        func consume(_ path: String) { for b in path.utf8 { hash = (hash ^ UInt64(b)) &* 1099511628211 }; pops += 1 }
        let start = ContinuousClock.now
        let repeats = scenario == "small" ? 2000 : 1
        for _ in 0..<repeats {
            for path in paths { queue.insert(path) }
            peakSlots = max(peakSlots, queue.slots)
            switch scenario {
            case "duplicates": for _ in 0..<4 { for path in paths { queue.insert(path) } }
            case "ancestors": for i in 0..<n { queue.insert("/fixture/branch-\(i)") }
            case "root": queue.insert("/fixture")
            case "churn":
                for i in 0..<(n * 4) {
                    if let path = queue.popFirst() { consume(path) }
                    queue.insert("/fixture/new-\(i)/leaf")
                }
            default: break
            }
            while let path = queue.popFirst() { consume(path) }
        }
        let elapsed = start.duration(to: .now).components
        return ["seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                "checksum": String(hash), "pops": pops, "peak_slots": peakSlots, "idle_slots": queue.slots]
    }
    static func main() throws {
        let a = CommandLine.arguments; let n = Int(a[3])!
        var row = a[1] == "legacy" ? run(LegacyRefreshQueue.self, scenario: a[2], n: n) : run(RefreshQueue.self, scenario: a[2], n: n)
        row["mode"] = a[1]; row["scenario"] = a[2]; row["n"] = n
        print(String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
    }
}
