import Foundation
import SpaceSnifferScanEngine
public struct WindowsNode: Codable, Sendable {
    public var id: Int
    public var parent: Int?
    public var name: String
    public var path: String
    public var directory: Bool
    public var logical: UInt64
    public var allocated: UInt64
    public var attributes: UInt32
    public var boundary: Bool
    public var error: UInt32?
    public var children: [Int]
    public var createdTicks: UInt64 = 0
    public var accessedTicks: UInt64 = 0
    public var modifiedTicks: UInt64 = 0
}
public struct WindowsSnapshot: Codable, Sendable {
    public var schema = 1
    public var root: String
    public var cancelled = false
    public var files = 0
    public var folders = 1
    public var errors = 0
    public var excluded = 0
    public var elapsedSeconds = 0.0
    public var volumeTotal: UInt64 = 0
    public var volumeFree: UInt64 = 0
    public var isVolumeRoot = false
    public var nodes: [WindowsNode]
}
public struct WindowsProgress: Encodable, Sendable {
    public let type = "progress"
    public let current: String
    public let files: Int
    public let folders: Int
    public let pending: Int
    public let errors: Int
    public let excluded: Int
    public let logical: UInt64
    public let allocated: UInt64
    public let roots: [WindowsOverviewEntry]
    public let rootFolderCount: Int
    public let overviewVersion = ScanOverviewPolicy.wireVersion
}

/// No child arrays: intermediate IPC stays bounded independently of a branch's size.
public struct WindowsOverviewEntry: Encodable, Sendable {
    public let name: String
    public let path: String
    public let directory: Bool
    public let logical: UInt64
    public let allocated: UInt64
    init(_ node: WindowsNode) {
        name=node.name;path=node.path;directory=node.directory;logical=node.logical;allocated=node.allocated
    }
}
