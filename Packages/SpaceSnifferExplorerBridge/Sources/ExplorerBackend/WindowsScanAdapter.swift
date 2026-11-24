#if os(Windows)
import Foundation
import ExplorerDomain
import WindowsScanCore

/// Windows traversal/refresh adapter. A focus request conservatively scans the root:
/// hard-link allocation currently depends on a scan-wide identity set. Reusing a
/// subtree without that set could double-count links outside the focused folder.
final class WindowsScanSession: @unchecked Sendable {
    let documents = DocumentService()
    private let includeMounted:Bool
    private let root: String
    private let output: URL
    private let binaryWire:Bool
    private let lock = NSLock()
    private var active: ScanControl?
    private var snapshot: ScanSnapshot?
    init(root: String, output: String,includeMounted:Bool = false,binaryWire:Bool = false) {self.binaryWire=binaryWire; self.includeMounted=includeMounted;self.root=root; self.output=URL(fileURLWithPath:output) }
    func cancel() { lock.lock(); let current=active; lock.unlock(); current?.cancel() }
    func scan(scope: String? = nil) {
        lock.lock()
        guard active == nil else { lock.unlock(); return }
        let original=snapshot
        if let scope {
            guard let original, let id=SnapshotTree.nodeID(at:scope,in:original), original.nodes[id].isDirectory else {
                lock.unlock(); bridgeEmit(["type":"failure","message":"재검사할 폴더가 현재 스냅샷에 없습니다."]); return
            }
        }
        let control=ScanControl(); active=control; lock.unlock()
        let worker=Thread { [self] in
            let scanned=WindowsScanner.scan(root:root,control:control,includeMountedVolumes:includeMounted,progress:{bridgeEmit($0)})
            do {
                let result=Self.convert(scanned,includeMounted:includeMounted)
                let version=try documents.publish(result,to:output,binary:binaryWire)
                lock.lock(); if !result.cancelled || snapshot == nil {snapshot=result}; active=nil; lock.unlock()
                bridgeEmit(["type":"complete","version":version,"output":output.path])
            } catch {
                lock.lock(); active=nil; lock.unlock()
                bridgeEmit(["type":"failure","message":error.localizedDescription])
            }
        }
        worker.start()
    }
    private static func convert(_ source: WindowsSnapshot,includeMounted:Bool) -> ScanSnapshot {
        func date(_ ticks: UInt64) -> Date? {ticks == 0 ? nil : Date(timeIntervalSince1970:Double(ticks)/10_000_000-11_644_473_600)}
        let nodes=source.nodes.map { n -> DiskNode in
            var node=DiskNode(id:n.id,parent:n.parent,path:n.path,name:n.name,isDirectory:n.directory,
                isSymbolicLink:n.boundary,logicalBytes:Int64(n.logical),allocatedBytes:Int64(n.allocated),
                children:n.children,issue:n.error.map {"Win32 \($0)"})
            node.ownAllocatedBytes=n.directory ? 0 : Int64(n.allocated)
            node.nativeAttributes=n.attributes;node.created=date(n.createdTicks);node.accessed=date(n.accessedTicks)
            node.modified=date(n.modifiedTicks) ?? .distantPast
            return node
        }
        var snapshot=ScanSnapshot(rootPath:source.root,nodes:nodes)
        snapshot.issues=Array(nodes.lazy.compactMap {node in node.issue.map {node.path+": "+$0}}.prefix(500))
        snapshot.fileCount=source.files;snapshot.folderCount=source.folders;snapshot.issueCount=source.errors
        var coverage=ScanVolumeCoverage(traversal:includeMounted ? .allVolumes : .selectedVolume)
        for node in nodes where node.isSymbolicLink {coverage.exclude(node.path,reason:"reparse_point")}
        snapshot.volumeCoverage=coverage
        snapshot.volumeTotal=Int64(clamping:source.volumeTotal);snapshot.volumeFree=Int64(clamping:source.volumeFree);snapshot.isVolumeRoot=source.isVolumeRoot
        snapshot.cancelled=source.cancelled;snapshot.finished=snapshot.started.addingTimeInterval(source.elapsedSeconds)
        return snapshot
    }
}
#endif
