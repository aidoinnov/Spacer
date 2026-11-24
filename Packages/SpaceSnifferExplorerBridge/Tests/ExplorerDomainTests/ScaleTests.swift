import Foundation
import XCTest
@testable import ExplorerDomain
final class ScaleTests:XCTestCase {
    func testLargeSNSRoundtripAndRepeatedNativeFiltering() throws {
        let environment=ProcessInfo.processInfo.environment
        let count=Int(environment["SNIFFER_GPUI_SCALE"] ?? "10000") ?? 10000
        guard (1000...2_000_000).contains(count) else {XCTFail("Invalid scale");return}
        var times:[String:Double]=[:]
        var start=ProcessInfo.processInfo.systemUptime
        var nodes=[DiskNode(id:0,parent:nil,path:"/scale",name:"scale",isDirectory:true,logicalBytes:Int64(count)*37,allocatedBytes:Int64(count)*4096)]
        nodes.reserveCapacity(count+count/1000+2)
        var remaining=count,branch=0
        while remaining>0 {
            let amount=environment["SNIFFER_GPUI_SCALE_FLAT"]=="1" ? remaining : min(1000,remaining);let id=nodes.count;let name="b\(branch)";let path="/scale/\(name)"
            nodes[0].children.append(id)
            nodes.append(DiskNode(id:id,parent:0,path:path,name:name,isDirectory:true,logicalBytes:Int64(amount)*37,allocatedBytes:Int64(amount)*4096))
            for index in 0..<amount {
                let child=nodes.count;let name="f\(index).bin"
                nodes[id].children.append(child)
                nodes.append(DiskNode(id:child,parent:id,path:path+"/"+name,name:name,logicalBytes:37,allocatedBytes:4096))
            }
            remaining-=amount;branch+=1
        }
        var snapshot=ScanSnapshot(rootPath:"/scale",nodes:nodes);nodes.removeAll()
        snapshot.fileCount=count;snapshot.folderCount=branch+1;snapshot.tags=["/scale/b0":4]
        times["buildMs"]=(ProcessInfo.processInfo.systemUptime-start)*1000
        start=ProcessInfo.processInfo.systemUptime
        let sns=try SNSSnapshot.encode(snapshot)
        times["encodeMs"]=(ProcessInfo.processInfo.systemUptime-start)*1000
        start=ProcessInfo.processInfo.systemUptime
        let restored=try SNSSnapshot.decode(sns)
        times["decodeMs"]=(ProcessInfo.processInfo.systemUptime-start)*1000
        XCTAssertEqual(restored.fileCount,count);XCTAssertEqual(restored.nodes.count,count+branch+1)
        XCTAssertEqual(restored.tags,snapshot.tags)
        var filterSamples=[Double]()
        for expression in ["",":green","*.bin;logicalsize>37b","|*.bin",":green"] {
            start=ProcessInfo.processInfo.systemUptime
            let weights=try ExplorerSemantics.weights(restored,text:expression,mode:.logical,hidden:true)
            filterSamples.append((ProcessInfo.processInfo.systemUptime-start)*1000)
            let expected:Int64=expression=="|*.bin" ? 0 : expression==":green" ? (environment["SNIFFER_GPUI_SCALE_FLAT"]=="1" ? Int64(count)*37 : 37_000) : Int64(count)*37
            XCTAssertEqual(weights[0],expected,expression)
        }
        if let output=environment["SNIFFER_GPUI_SCALE_OUTPUT"] {
            let path=URL(fileURLWithPath:output)
            let document=path.deletingPathExtension().appendingPathExtension("sns")
            try sns.write(to:document,options:.atomic)
            let report:[String:Any]=["passed":true,"files":count,"nodes":restored.nodes.count,"snsBytes":sns.count,"timings":times,"filterMs":filterSamples,"sns":document.path]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:path,options:.atomic)
        }
    }
}
