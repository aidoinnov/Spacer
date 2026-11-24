import Foundation
import SpaceSnifferCore
import SpaceSnifferAutomation

/// Same 10 target files, with unrelated siblings added outside the query scope.
@main enum MCPQueryAudit {
    static func main() throws {
        let unrelated = Int(CommandLine.arguments.dropFirst().first ?? "250000")!
        var s = ScanSnapshot(rootPath:"/audit")
        s.nodes.append(DiskNode(id:0,parent:nil,path:"/audit",name:"audit",isDirectory:true,logicalBytes:Int64(unrelated+10),allocatedBytes:Int64(unrelated+10)))
        s.nodes.append(DiskNode(id:1,parent:0,path:"/audit/target",name:"target",isDirectory:true,logicalBytes:10,allocatedBytes:10))
        s.nodes[0].children.append(1)
        for i in 0..<10 {
            let id=s.nodes.count;s.nodes[1].children.append(id)
            s.nodes.append(DiskNode(id:id,parent:1,path:"/audit/target/f-\(i).bin",name:"f-\(i).bin",logicalBytes:1,allocatedBytes:1))
        }
        for i in 0..<unrelated {
            let id=s.nodes.count;s.nodes[0].children.append(id)
            s.nodes.append(DiskNode(id:id,parent:0,path:"/audit/unrelated-\(i).bin",name:"unrelated-\(i).bin",logicalBytes:1,allocatedBytes:1))
        }
        let context=QueryContext(snapshot:s,weights:s.nodes.map(\.logicalBytes),filter:try ScanFilter(""),mode:.logical,showHidden:true,revision:"audit",focus:0,selection:nil)
        let start=ProcessInfo.processInfo.systemUptime
        let value=try context.query(command:"largest_nodes",arguments:["path":.string("/audit/target"),"limit":.int(10)])
        let elapsed=ProcessInfo.processInfo.systemUptime-start
        guard case .array(let rows)=value.object?["items"] else { fatalError() }
        precondition(rows.count==10)
        print(String(decoding:try JSONSerialization.data(withJSONObject:["scenario":"mcp_scoped_largest","unrelated_files":unrelated,"target_files":10,"seconds":elapsed,"returned":rows.count],options:.sortedKeys),as:UTF8.self))
    }
}
