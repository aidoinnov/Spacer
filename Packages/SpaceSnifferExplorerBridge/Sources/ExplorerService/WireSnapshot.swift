import Foundation
#if canImport(SpaceSnifferCore)
import SpaceSnifferCore
#else
import ExplorerDomain
#endif
struct WireNode: Encodable {
    var modified: Double; var created: Double?; var accessed: Double?
    var nativeType: UInt8?; var nativeFlags: UInt8?
    var id: Int; var parent: Int?; var name: String; var path: String?
    var directory: Bool; var logical: Int64; var allocated: Int64
    var attributes: UInt32; var boundary: Bool; var error: String?; var children: [Int]
}
struct WireSnapshot: Encodable {
    let schema = 1
    var wireVersion:String?
    var root: String; var cancelled: Bool; var files: Int; var folders: Int
    var errors: Int; var excluded: Int; var elapsedSeconds: Double
    var volumeTotal: Int64; var volumeFree: Int64; var isVolumeRoot: Bool
    var nodes: [WireNode]
    var issues:[String]
    var tags: [String:Int]
    var volumeTraversal:String?
    init(_ source: ScanSnapshot,version:String? = nil) {
        wireVersion=version
        issues=Array(source.issues.prefix(500))
        tags=source.tags
        volumeTraversal=source.volumeCoverage?.traversal.rawValue
        root=source.rootPath;cancelled=source.cancelled;files=source.fileCount;folders=source.folderCount
        errors=source.issueCount;excluded=source.volumeCoverage?.excludedCount ?? 0
        elapsedSeconds=(source.finished ?? Date()).timeIntervalSince(source.started)
        volumeTotal=source.volumeTotal;volumeFree=source.volumeFree;isVolumeRoot=source.isVolumeRoot
        nodes=source.nodes.map { n in WireNode(modified:n.modified.timeIntervalSince1970,created:n.created?.timeIntervalSince1970,accessed:n.accessed?.timeIntervalSince1970,nativeType:n.nativeType,nativeFlags:n.nativeFlags,id:n.id,parent:n.parent,name:n.name,path:n.id == 0 ? n.path : nil,
            directory:n.isDirectory,logical:n.logicalBytes,allocated:n.allocatedBytes,
            attributes:n.nativeAttributes ?? (n.name.hasPrefix(".") ? 2 : 0),boundary:n.isSymbolicLink,error:n.issue,children:n.children) }
    }
}
