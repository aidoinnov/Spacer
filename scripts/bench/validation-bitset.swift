import Foundation
import Darwin

@main enum ValidationProbe {
    static func fixture(_ count:Int) -> ScanSnapshot {
        var s=ScanSnapshot(rootPath:"/validation"); s.folderCount=1; s.fileCount=count-1
        s.nodes.append(DiskNode(id:0,parent:nil,path:s.rootPath,name:"validation",isDirectory:true,logicalBytes:Int64(count-1),allocatedBytes:Int64(count-1),children:Array(1..<count)))
        for i in 1..<count { s.nodes.append(DiskNode(id:i,parent:0,path:"/validation/n\(i)",name:"n\(i)",logicalBytes:1,allocatedBytes:1)) }
        return s
    }
    static func emit(_ value:[String:Any]) throws { print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),as:UTF8.self)) }
    static func accepted(_ s:ScanSnapshot,_ legacy:Bool) -> Bool { do { _ = try legacy ? s.frozenSetValidated() : s.validated(); return true } catch { return false } }
    static func main() async throws {
        let a=CommandLine.arguments; precondition(a.count>=2); let mode=a[1]
        if mode=="self-test" {
            var checks=0
            for n in [1,2,7,8,9,63,64,65,255,256,257,1025] { let s=fixture(n); precondition(accepted(s,true) && accepted(s,false)); checks+=1 }
            var seed:UInt64=0x56414c4944415445
            for _ in 0..<2000 {
                seed=seed &* 6364136223846793005 &+ 1; var s=fixture(65); let i=Int((seed>>8)%64)+1
                switch seed%12 {
                case 0:s.nodes[0].children.append(i)
                case 1:s.nodes[0].children.remove(at:i-1)
                case 2:s.nodes[i].parent=Int(seed%67)-1
                case 3:s.nodes[i].id=Int(seed%67)
                case 4:s.nodes[i].allocatedBytes=Int64(seed%4)-1
                case 5:s.nodes[i].name="odd/\(i)"
                case 6:s.tags["x"]=Int(seed%18)
                case 7:s.nodes[1].logicalBytes=Int64.max;s.nodes[0].logicalBytes=Int64.max
                case 8:s.nodes[1].ownAllocatedBytes = -1
                case 9:s.nodes[0].children=[Int.max]
                case 10:s.fileCount=Int.max;s.folderCount=0;s.issueCount=Int.max
                default:break
                }
                precondition(accepted(s,true)==accepted(s,false));checks+=1
            }
            let control=ScanControl();control.cancel()
            do { _ = try fixture(1).validated(control:control); fatalError("cancellation missing") } catch is CancellationError {} catch { fatalError("wrong error") }
            try emit(["status":"PASS","oracle_checks":checks,"pre_cancel":"CancellationError","scope":"independent frozen Set oracle, malformed/overflow/count and byte-boundary checks; not Windows runtime"]);return
        }
        if mode=="cancel" {
            var rows:[[String:Any]]=[]
            for phase in ["edges","nodes","tags"] {
                var s=fixture(250_000)
                if phase=="nodes" { s.nodes[0].children=[] }
                if phase=="tags" { s=fixture(1);s.tags=Dictionary(uniqueKeysWithValues:(0..<250_000).map { ("tag-\($0)",1) }) }
                let frozen=s, control=ScanControl(), entered=DispatchSemaphore(value:0), ready=DispatchSemaphore(value:0)
                DispatchQueue.global(qos:.userInitiated).async {
                    ready.signal(); entered.wait(); Thread.sleep(forTimeInterval:0.0001);control.cancel()
                }
                precondition(ready.wait(timeout:.now()+2) == .success)
                let start=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                let task=Task.detached { () -> Bool in
                    entered.signal()
                    do { _ = try frozen.validated(control:control); return false } catch is CancellationError { return true } catch { return false }
                }
                let cancelled=await task.value;precondition(cancelled)
                rows.append(["phase_input":phase,"cancelled":cancelled,"seconds_from_worker_submission":Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-start)/1e9])
            }
            try emit(["status":"PASS","rows":rows,"scope":"concurrent timing cancellation on edge-heavy, node-heavy and tag-heavy inputs; exact loop phase at cancellation is not instrumented"]);return
        }
        precondition(a.count==4);let input=a[2],iterations=Int(a[3])!
        let buildStart=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let snapshot:ScanSnapshot
        if let count=Int(input) { snapshot=fixture(count) }
        else { snapshot=try SNSSnapshot.decode(Data(contentsOf:URL(fileURLWithPath:input),options:.mappedIfSafe)) }
        let prepareSeconds=Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-buildStart)/1e9
        var before=rusage();getrusage(RUSAGE_SELF,&before)
        let start=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);var checksum=0
        for _ in 0..<iterations {
            let result=try mode=="set" ? snapshot.frozenSetValidated() : snapshot.validated()
            checksum &+= result.nodes.count
        }
        let seconds=Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-start)/1e9
        var after=rusage();getrusage(RUSAGE_SELF,&after)
        try emit(["mode":mode,"input":input,"nodes":snapshot.nodes.count,"iterations":iterations,"prepare_seconds":prepareSeconds,"validation_seconds":seconds,"checksum":checksum,"max_rss_before_bytes":before.ru_maxrss,"max_rss_after_bytes":after.ru_maxrss,"bitset_payload_bytes":snapshot.nodes.count/8+(snapshot.nodes.count%8==0 ? 0:1),"scope":"fresh process, identical optimized copied Core; peak RSS includes fixture/decode, before/after are high-water marks not exclusive allocation attribution; host GUI/agents concurrent"])
    }
}
