import XCTest
@testable import SpaceSnifferCore

final class SnapshotValidationBitsetTests: XCTestCase, @unchecked Sendable {
    func fixture(_ count: Int) -> ScanSnapshot {
        var s=ScanSnapshot(rootPath:"/validation"); s.folderCount=1; s.fileCount=count-1
        s.nodes.append(DiskNode(id:0,parent:nil,path:s.rootPath,name:"validation",isDirectory:true,
                               logicalBytes:Int64(count-1),allocatedBytes:Int64(count-1),children:Array(1..<count)))
        for i in 1..<count { s.nodes.append(DiskNode(id:i,parent:0,path:"/validation/n\(i)",name:"n\(i)",logicalBytes:1,allocatedBytes:1)) }
        return s
    }
    private func accepts(_ snapshot: ScanSnapshot, legacy: Bool) -> Bool {
        do { _ = try legacy ? snapshot.frozenSetValidated() : snapshot.validated(); return true } catch { return false }
    }
    func testIndependentFrozenOracleAcrossBitBoundariesAndUnspecifiedCounts() throws {
        for count in [1,2,7,8,9,63,64,65,255,256,257,1025] {
            var value=fixture(count); value.tags=["not-required-to-exist":15]
            // Original guards require nonnegative counts, not exact recounts.
            value.fileCount=Int.max; value.folderCount=0; value.issueCount=Int.max
            XCTAssertTrue(accepts(value,legacy:true)); XCTAssertTrue(accepts(value,legacy:false))
            XCTAssertEqual(Array(try value.validated().nodes),Array(value.nodes))
        }
    }
    func testMalformedCasesKeepFrozenAcceptanceAndErrorClass() throws {
        let base=fixture(9)
        var cases:[ScanSnapshot]=[]
        func add(_ mutate:(inout ScanSnapshot)->Void) { var value=base; mutate(&value); cases.append(value) }
        add { $0.nodes[0].children.append(1) } // duplicate within a parent
        add { $0.nodes[0].children.removeLast() } // missing incoming edge
        add { $0.nodes[0].children=[0] } // root/self incoming
        add { $0.nodes[0].children=[Int.max] }
        add { $0.nodes[0].children=[-1] }
        add { $0.nodes[1].id=3 }
        add { $0.nodes[1].parent=nil }
        add { $0.nodes[1].parent=2 }
        add { $0.nodes[1].path="/outside/n1" }
        add { $0.nodes[1].name=".." }
        add { $0.nodes[1].logicalBytes = -1 }
        add { $0.nodes[1].ownAllocatedBytes = -1 }
        add { $0.nodes[0].isDirectory=false }
        add { $0.nodes[0].logicalBytes=0 }
        add { $0.tags["x"]=0 }
        add { $0.tags["x"]=16 }
        add { $0.fileCount = -1 }
        add { $0.folderCount = -1 }
        add { $0.issueCount = -1 }
        add { $0.volumeFree = -1 }
        add { $0.version=2 }
        add { $0.nodes[0].parent=0 }
        add { $0.nodes[0].path="/other" }
        add { $0.nodes[1].logicalBytes=Int64.max; $0.nodes[2].logicalBytes=1; $0.nodes[0].logicalBytes=Int64.max }
        add { $0.nodes[1].allocatedBytes=Int64.max; $0.nodes[2].allocatedBytes=1; $0.nodes[0].allocatedBytes=Int64.max }
        add { $0.nodes[1].isDirectory=true; $0.nodes[1].children=[2] } // child parent mismatch/cross-parent duplicate
        add { $0.nodes=NodeTable() }
        for (index,value) in cases.enumerated() {
            XCTAssertFalse(accepts(value,legacy:true),"oracle case \(index)")
            XCTAssertFalse(accepts(value,legacy:false),"candidate case \(index)")
            XCTAssertThrowsError(try value.validated()) { XCTAssertTrue($0 is SnapshotError) }
        }
    }
    func testSeededMutationCorpusMatchesFrozenOracle() {
        var seed:UInt64=0x56414c4944415445
        for _ in 0..<1000 {
            seed=seed &* 6364136223846793005 &+ 1
            var value=fixture(65); let i=Int((seed>>8)%64)+1
            switch seed%8 {
            case 0: value.nodes[0].children.append(i)
            case 1: value.nodes[0].children.remove(at:i-1)
            case 2: value.nodes[i].parent=Int(seed%67)-1
            case 3: value.nodes[i].id=Int(seed%67)
            case 4: value.nodes[i].allocatedBytes=Int64(seed%4)-1
            case 5: value.nodes[i].name="odd/\(i)"
            case 6: value.tags["x"]=Int(seed%18)
            default: break
            }
            XCTAssertEqual(accepts(value,legacy:false),accepts(value,legacy:true))
        }
    }
    func testPrecancelledValidAndMalformedInputsThrowCancellation() {
        let control=ScanControl(); control.cancel()
        XCTAssertThrowsError(try fixture(1).validated(control:control)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try ScanSnapshot(rootPath:"relative").validated(control:control)) { XCTAssertTrue($0 is CancellationError) }
    }
    func testCancellationDuringLargeEdgeNodeAndTagWalks() async throws {
        for phase in ["edges","nodes","tags"] {
            var value=fixture(250_000)
            if phase=="nodes" { value.nodes[0].children=[] } // Deferred missing-incoming error; no wide edge walk.
            if phase=="tags" {
                value=fixture(1)
                value.tags=Dictionary(uniqueKeysWithValues:(0..<250_000).map { ("tag-\($0)",1) })
            }
            let frozen=value, control=ScanControl(), started=DispatchSemaphore(value:0), ready=DispatchSemaphore(value:0)
            DispatchQueue.global(qos:.userInitiated).async {
                ready.signal(); started.wait(); Thread.sleep(forTimeInterval:0.0001); control.cancel()
            }
            XCTAssertEqual(ready.wait(timeout:.now()+2),.success)
            let task=Task.detached { () -> Bool in
                started.signal()
                do { _ = try frozen.validated(control:control); return false }
                catch is CancellationError { return true }
                catch { return false }
            }
            // Dedicated ready canceller avoids cooperative/main-actor sleep
            // resumption occurring after validation already completed. Exact
            // phase/ID at cancellation remains intentionally uninstrumented.
            let cancelled=await task.value; XCTAssertTrue(cancelled,phase)
        }
    }
}
