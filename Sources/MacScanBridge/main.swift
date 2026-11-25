import Foundation
import Dispatch
import SpaceSnifferCore

// A wire adapter, not another scanner. All traversal, metadata, accounting and
// cancellation remain in the existing validated SpaceSnifferCore engine.
struct WireOverview: Encodable {
    var name: String; var path: String; var directory = true; var logical: Int64; var allocated: Int64
}
struct WireProgress: Encodable {
    let type = "progress"
    var current: String; var files: Int; var folders: Int; var pending: Int
    var errors: Int; var excluded:Int? = nil; var logical: Int64; var allocated: Int64; var roots: [WireOverview]
    var overviewVersion: Int? = nil
    var rootFolderCount: Int? = nil
}
let args=CommandLine.arguments
ParentLifetime.install(args)
if args.count == 2 && args[1] == "--layout-oracle" {
    let cases: [[Double]] = [[3,1],[10,9,8,7,6,5,4,3,2,1],[1000,1,1,1],[5,5,5,5],[1]]
    let output: [[String: Any]] = cases.map { weights in
        let tiles=Treemap.layout(weights.enumerated().map { ($0.offset,$0.element) },in:CGRect(x:10,y:20,width:800,height:500))
        return ["weights":weights,"tiles":tiles.map { ["id":Double($0.id),"x":$0.rect.minX,"y":$0.rect.minY,"w":$0.rect.width,"h":$0.rect.height] }]
    }
    let result: [String: Any] = ["cases":output,"motion":[0.0,0.25,0.5,0.75,1.0].map { ["fraction":$0,"progress":TreemapMotion.progress($0)] }]
    let bytes=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);FileHandle.standardOutput.write(bytes);exit(0)
}
if try runSnapshotImport(args) { exit(0) }
if runDocumentService(args){exit(0)}
if args.count < 5 || args[1] != "--scan" || args[3] != "--output" {
    FileHandle.standardError.write(Data("MacScanBridge --scan ROOT --output SNAPSHOT.json\n".utf8));exit(64)
}
actor BridgeSession {
    let service:ScanService
    nonisolated let documents = DocumentService()
    let root: URL
    let output: String
    let binaryWire:Bool
    var watching: Bool
    var subscription: ScanSubscription?
    var pendingStop=false
    var publishedWatch:Bool?
    var publishedRevision:UInt64?
    var awaitingCompletion=false
    init(root: String, output: String, watching: Bool, traversal:ScanVolumeTraversal,binaryWire:Bool) {
        self.service=ScanService(volumeTraversal:traversal)
        self.root=URL(fileURLWithPath:root);self.output=output;self.watching=watching;self.binaryWire=binaryWire
    }
    func run() async {
        let sub=await service.subscribe(root,watching:watching);subscription=sub
        if pendingStop {await service.stop(rootPath:sub.rootPath)}
        for await update in sub.updates {
            if publishedWatch != update.watchActive {
                struct Watch:Encodable {let type="watchState";let active:Bool}
                bridgeEmit(Watch(active:update.watchActive));publishedWatch=update.watchActive
            }
            if update.isScanning {awaitingCompletion=true}
            if let p=update.progress, update.isScanning {
                let overview = p.overview
                func candidates(_ allocated: [ScanOverviewItem], _ logical: [ScanOverviewItem], directory: Bool) -> [WireOverview] {
                    var seen = Set<Int>()
                    return (allocated + logical).filter { seen.insert($0.id).inserted }.map {
                        WireOverview(name:$0.name,path:$0.path,directory:directory,logical:$0.logicalBytes,allocated:$0.allocatedBytes)
                    }
                }
                let folders = candidates(overview?.folders ?? [], overview?.logicalFolders ?? [], directory: true)
                let files = candidates(overview?.largeFiles ?? [], overview?.logicalLargeFiles ?? [], directory: false)
                bridgeEmit(WireProgress(current:p.currentPath,files:p.fileCount,folders:p.folderCount,pending:p.pendingFolders,
                    errors:p.issueCount,logical:p.logicalBytes,allocated:p.allocatedBytes,roots:folders+files,
                    overviewVersion: overview == nil ? nil : ScanOverview.wireVersion, rootFolderCount: overview?.rootFolderCount))
            }
            if !update.isScanning && (awaitingCompletion || publishedRevision != update.revision) {
                do {
                    let version=try documents.publish(update.snapshot,to:URL(fileURLWithPath:output),binary:binaryWire)
                    publishedRevision=update.revision;awaitingCompletion=false
                    bridgeEmit(["type":"complete","version":version,"output":output,"cancelled":update.snapshot.cancelled ? "true":"false"])
                }catch {bridgeEmit(["type":"failure","message":error.localizedDescription])}
            }
        }
    }
    func command(_ line: String) async {
        if line=="quit" && subscription==nil {exit(0)}
        guard let sub=subscription else {if line=="cancel"{pendingStop=true};return}
        if line=="cancel" {await service.stop(rootPath:sub.rootPath)}
        else if line=="watch true" || line=="watch false" {watching=line=="watch true";await service.setWatching(watching,subscription:sub)}
        else if line=="rescan" {await service.rescan(rootPath:sub.rootPath)}
        else if ScopedRescanCommand.matches(line) {
            do {
                let scope = try ScopedRescanCommand.path(line)
                if await service.requestFocusRescan(subscription:sub,scope:scope) == nil {
                    bridgeEmit(["type":"failure","message":"재검사할 폴더가 현재 스냅샷에 없습니다."])
                }
            } catch { bridgeEmit(["type":"failure","message":"잘못된 재검사 경로입니다."]) }
        }
        else if line=="quit" {
            await service.unsubscribe(sub.id,rootPath:sub.rootPath)
            for _ in 0..<100 {if await service.statistics().admission.active==0{exit(0)};try? await Task.sleep(for:.milliseconds(20))}
            exit(0)
        }
    }
}
let watching=args.firstIndex(of:"--watch").map {args.indices.contains($0+1) && args[$0+1]=="true"} ?? false
var traversal=ScanVolumeTraversal.selectedVolume
if let index=args.firstIndex(of:"--volumes") {
    guard args.indices.contains(index+1),let value=ScanVolumeTraversal(rawValue:args[index+1]) else {exit(64)}
    traversal=value
}
let bridge=BridgeSession(root:args[2],output:args[4],watching:watching,traversal:traversal,binaryWire:usesBinaryWire(args))
Task {await bridge.run()}
let input=Thread {while let line=readLine(){if !bridge.documents.handle(line) {Task {await bridge.command(line)}}};Task {await bridge.command("quit")}};input.start()
dispatchMain()
