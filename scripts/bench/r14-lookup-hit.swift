import Foundation
import CoreGraphics
import Darwin

@inline(never) func first(_ names: [String], _ target: String, _ comparisons: inout Int) -> Int? {
    for index in names.indices { comparisons += 1; if names[index] == target { return index } }; return nil
}
@inline(never) func hinted(_ names: [String], _ target: String, hint: Int, _ comparisons: inout Int) -> Int? {
    guard !names.isEmpty else { return nil }
    var left = names.indices.contains(hint) ? hint : names.count / 2; var right = left + 1
    while left >= 0 || right < names.count {
        if left >= 0 { comparisons += 1; if names[left] == target { return left }; left -= 1 }
        if right < names.count { comparisons += 1; if names[right] == target { return right }; right += 1 }
    }; return nil
}
struct Item { let rect: CGRect; let parent: Int?; var interactive = true; var opacity = 1.0; var identityValid = true }
@inline(never) func flat(_ items: [Item], _ point: CGPoint, _ comparisons: inout Int) -> Int? {
    for index in items.indices.reversed() {
        comparisons += 1; let value = items[index]
        if value.interactive && value.opacity > 0.5 && value.identityValid && value.rect.contains(point) { return index }
    }; return nil
}
struct Hierarchy {
    let items: [Item]; let children: [[Int]]; let roots: [Int]
    init(_ items: [Item]) {
        self.items = items; var children = [[Int]](repeating: [], count: items.count); var roots: [Int] = []
        for index in items.indices { if let parent = items[index].parent { children[parent].append(index) } else { roots.append(index) } }
        self.children = children; self.roots = roots
    }
    @inline(never) func hit(_ point: CGPoint, comparisons: inout Int) -> Int? {
        func descend(_ index: Int) -> Int? {
            comparisons += 1; let value = items[index]
            guard value.rect.contains(point) else { return nil }
            // Reverse order preserves the current Mac flat last-painted oracle.
            for child in children[index].reversed() { if let found = descend(child) { return found } }
            return value.interactive && value.opacity > 0.5 && value.identityValid ? index : nil
        }
        for index in roots.reversed() { if let value = descend(index) { return value } }; return nil
    }
}
func emit(_ value: [String: Any]) { print(String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)) }
func elapsed(_ start: UInt64) -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-start)/1e9 }
let args = CommandLine.arguments; precondition(args.count >= 5)
let kind = args[1], mode = args[2], count = Int(args[3])!, scenario = args[4]
var generator: UInt64 = 0x534e4946464552
func random(_ bound: Int) -> Int { generator = generator &* 6364136223846793005 &+ 1442695040888963407; return Int(generator >> 16) % bound }
if kind == "lookup" {
    let names = (0..<count).map { "item-\($0)-data.bin" }
    let indices = (0..<500).map { scenario == "localized" ? (count/2+$0%256)%count : random(count) }
    let targets = indices.map { String(decoding: Array(names[$0].utf8), as: UTF8.self) }
    var checks = 0; var hint = count/2
    for (index, target) in zip(indices, targets) {
        precondition(first(names,target,&checks) == index)
        precondition(hinted(names,target,hint:hint,&checks) == index); hint = index
    }
    let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW); var comparisons = 0; var checksum = 0; hint = count/2
    for target in targets {
        let found = mode == "first" ? first(names,target,&comparisons) : hinted(names,target,hint:hint,&comparisons)
        checksum &+= found ?? -1; if let found { hint = found }
    }
    let seconds = elapsed(start); var a=0,b=0
    let duplicate = ["zero","same","other","same"]
    emit(["probe":kind,"mode":mode,"scenario":scenario,"count":count,"operations":targets.count,"seconds":seconds,"comparisons":comparisons,"checksum":checksum,
        "duplicate_first":first(duplicate,"same",&a)!,"duplicate_hint":hinted(duplicate,"same",hint:3,&b)!,
        "scope":"pure instrumented String lookup kernel; inputs+500 independent expected-ID checks outside time; duplicate-name boundary intentionally differs; no production change or end-to-end claim"])
} else {
    let groups = min(64,max(1,count/33)); var items: [Item] = []; let begin = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    for group in 0..<groups {
        let x = Double(group)*1000/Double(groups); let width = 1000/Double(groups); let parent = items.count
        items.append(Item(rect: CGRect(x:x,y:0,width:width,height:1000),parent:nil))
        let leaves=(count-groups)/groups+(group < (count-groups)%groups ? 1:0)
        for leaf in 0..<leaves {
            let height=980/Double(leaves); let id=items.count
            items.append(Item(rect:CGRect(x:x+0.1,y:20+Double(leaf)*height,width:width-0.2,height:height-0.1),parent:parent,
                interactive:id%37 != 0,opacity:id%41 == 0 ? 0.4:1,identityValid:id%43 != 0))
        }
    }
    precondition(items.count==count); let hierarchy=Hierarchy(items); let build=elapsed(begin)
    let points=(0..<10_000).map { _ in CGPoint(x:Double(random(1_000_000))/1000,y:Double(random(1_000_000))/1000) }
    var checks=0
    for p in points { precondition(flat(items,p,&checks)==hierarchy.hit(p,comparisons:&checks)) }
    let start=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);var comparisons=0;var checksum=0
    for p in points { checksum &+= (mode=="flat" ? flat(items,p,&comparisons):hierarchy.hit(p,comparisons:&comparisons)) ?? -1 }
    let seconds=elapsed(start)
    let adversarial=[Item(rect:CGRect(x:0,y:0,width:100,height:100),parent:nil),Item(rect:CGRect(x:150,y:0,width:20,height:20),parent:0)]
    let boundary=CGPoint(x:155,y:5);var a=0,b=0
    emit(["probe":kind,"mode":mode,"scenario":scenario,"count":count,"operations":points.count,"seconds":seconds,"comparisons":comparisons,"checksum":checksum,"index_build_seconds":build,
        "child_id_payload_bytes":(count-groups)*MemoryLayout<Int>.stride,"child_array_handles_bytes":count*MemoryLayout<[Int]>.stride,
        "out_of_parent_flat":flat(adversarial,boundary,&a) as Any? ?? NSNull(),"out_of_parent_hierarchy":Hierarchy(adversarial).hit(boundary,comparisons:&b) as Any? ?? NSNull(),
        "scope":"stable nested synthetic rectangles with current Mac reverse-paint oracle, all points within viewport; opacity/interaction/identity gates. Includes adversarial containment counterexample; not actual AppKit input or animation performance"])
}
