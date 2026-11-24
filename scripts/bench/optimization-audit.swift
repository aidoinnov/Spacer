import Foundation

/// Metadata-only audit. Alternatives are probes, not shipped engine implementations.
/// Build with SpaceSnifferCore sources in the same module to inspect internal phases.
@main enum OptimizationAudit {
    static func main() throws {
        let scenario = CommandLine.arguments.dropFirst().first ?? "navigation"
        let count = Int(CommandLine.arguments.dropFirst(2).first ?? "250000")!
        if scenario == "queue" {
            var q = RefreshQueue()
            let start = ProcessInfo.processInfo.systemUptime
            for i in 0..<count { q.insert("/audit/branch-\(i)/leaf") }
            let insert = ProcessInfo.processInfo.systemUptime - start
            let popStart = ProcessInfo.processInfo.systemUptime
            var popped = 0
            while q.popFirst() != nil { popped += 1 }
            precondition(popped == count)
            emit(["scenario":scenario,"requests":count,"insert_seconds":insert,"drain_seconds":ProcessInfo.processInfo.systemUptime-popStart])
            return
        }
        var s = ScanSnapshot(rootPath: "/audit")
        s.nodes.append(DiskNode(id:0,parent:nil,path:s.rootPath,name:"audit",isDirectory:true,logicalBytes:Int64(count),allocatedBytes:Int64(count)*4096))
        let folders = 100
        let perFolder = count / folders
        precondition(perFolder > 0 && count % folders == 0)
        for f in 0..<folders {
            let id = s.nodes.count; s.nodes[0].children.append(id)
            let path = "/audit/branch-\(f)"
            s.nodes.append(DiskNode(id:id,parent:0,path:path,name:"branch-\(f)",isDirectory:true,logicalBytes:Int64(perFolder),allocatedBytes:Int64(perFolder)*4096))
            for file in 0..<perFolder {
                let child = s.nodes.count; s.nodes[id].children.append(child)
                let name = "file-\(file)." + (file % 2 == 0 ? "bin" : "txt")
                s.nodes.append(DiskNode(id:child,parent:id,path:path+"/"+name,name:name,logicalBytes:1,allocatedBytes:4096))
            }
        }
        s.fileCount = count; s.folderCount = folders + 1
        let filter = try ScanFilter("*.bin")
        let control = ScanControl()
        let included = filter.membership(in:s,showHidden:true)!
        let weights = filter.weights(in:s,mode:.logical,included:included)
        let repeats = 10
        var times:[String:Double]=[:]; var checksum:Int64=0
        if scenario == "navigation" {
            var start = ProcessInfo.processInfo.systemUptime
            for i in 0..<repeats {
                let p = FilterProjection(snapshot:s,filter:filter,mode:.logical,showHidden:true,focusPath:"/audit/branch-\(i)",selectionPath:nil,previous:s,history:[s.rootPath],historyIndex:0,control:control)!
                checksum += p.weights[p.focus]; precondition(p.children.count == perFolder/2)
            }
            times["full_projection_seconds"] = ProcessInfo.processInfo.systemUptime-start
            start = ProcessInfo.processInfo.systemUptime
            var alternative:Int64=0
            for i in 0..<repeats {
                let n = NavigationState(snapshot:s,previous:s,included:included,weights:weights,focusPath:"/audit/branch-\(i)",selectionPath:nil,history:[s.rootPath],historyIndex:0,control:control)!
                let children = s.nodes[n.focus].children.filter { weights[$0]>0 }.sorted { weights[$0] == weights[$1] ? $0<$1 : weights[$0]>weights[$1] }
                alternative += weights[n.focus];precondition(children.count == perFolder/2)
            }
            times["reuse_membership_weights_seconds"] = ProcessInfo.processInfo.systemUptime-start
            precondition(checksum==alternative)
        } else if scenario == "export" {
            let start = ProcessInfo.processInfo.systemUptime
            let ids = filter.matchingIDs(in:s,showHidden:true,root:1)
            let w = filter.weights(in:s,mode:.logical,showHidden:true)
            let text = Report.simpleFileList(s,ids:Set(ids),weights:w,root:1)
            times["current_scope_export_seconds"] = ProcessInfo.processInfo.systemUptime-start
            checksum = Int64(text.utf8.count)
            precondition(ids.count == perFolder/2+1)
            // Isolate existing repeated membership work, without changing output generation.
            let t = ProcessInfo.processInfo.systemUptime
            let membership = filter.membership(in:s,showHidden:true)!
            let matches = membership.reduce(0) { $0 + ($1 ? 1 : 0) }
            precondition(matches == count / 2)
            times["one_membership_plus_checksum_seconds"] = ProcessInfo.processInfo.systemUptime-t
        } else if scenario == "treemap" {
            let start = ProcessInfo.processInfo.systemUptime
            let tiles = Treemap.tiles(snapshot:s,weights:weights,root:1,depth:3,selected:nil,in:CGRect(x:0,y:0,width:1200,height:800),control:control)!
            times["geometry_seconds"] = ProcessInfo.processInfo.systemUptime-start
            checksum=Int64(tiles.count)
        } else { fatalError("unknown scenario") }
        emit(["scenario":scenario,"files":count,"nodes":s.nodes.count,"repeats":scenario=="navigation" ? repeats:1,"times":times,"checksum":checksum])
    }
    static func emit(_ object:[String:Any]) {
        print(String(decoding:try! JSONSerialization.data(withJSONObject:object,options:.sortedKeys),as:UTF8.self))
    }
}
