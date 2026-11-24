import Foundation
import SpaceSnifferCore

/// Fixed synthetic metadata; disk fixtures are deliberately separate and small.
public enum OptimizationFixture {
    public enum Shape: String, CaseIterable { case small, wide, deep, balanced, edges }
    public static let seed: UInt64 = 0x534e4946464552
    public static func metadata(files: Int = 250_000, shape: Shape = .balanced) -> ScanSnapshot {
        precondition(files >= 0 && files <= 250_000)
        var result = ScanSnapshot(rootPath: "/fixture")
        result.started = Date(timeIntervalSince1970: 1_700_000_000); result.finished = result.started
        result.nodes.append(DiskNode(id: 0, parent: nil, path: "/fixture", name: "fixture", isDirectory: true))
        let branches = shape == .wide ? 0 : shape == .deep ? 32 : min(100, max(1, files / 100))
        for index in 0..<branches {
            let parent = shape == .deep ? index : 0
            let id = result.nodes.count; let name = "branch-\(index)"
            result.nodes.append(DiskNode(id: id, parent: parent, path: result.nodes[parent].path + "/" + name, name: name, isDirectory: true))
            result.nodes[parent].children.append(id)
        }
        var random = seed
        for index in 0..<files {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            let parent = branches == 0 ? 0 : shape == .deep ? branches : 1 + index % branches
            let id = result.nodes.count
            let edgeNames = ["zero.bin", "café.bin", "cafe\u{301}.txt", "한글.bin", "UPPER.BIN", "lower.txt", ".hidden.bin", String(repeating: "long", count: 50) + ".bin"]
            let name = shape == .edges ? "\(index)-" + edgeNames[index % edgeNames.count] : "file-\(index)." + (index % 3 == 0 ? "txt" : "bin")
            let size = shape == .edges ? Int64([0, 1, 1023, 1024, 1025, 1_048_576][index % 6]) : Int64(random % 65536)
            var node = DiskNode(id: id, parent: parent, path: result.nodes[parent].path + "/" + name, name: name, logicalBytes: size, allocatedBytes: size == 0 ? 0 : ((size + 4095) / 4096) * 4096, modified: Date(timeIntervalSince1970: 1_699_999_000))
            node.fileIdentity = "device:inode-\(index)"; node.created = Date(timeIntervalSince1970: 1_690_000_000); node.accessed = node.modified
            if shape == .edges, index % 7 == 0 { node.nativeAttributes = 2 }
            result.nodes.append(node); result.nodes[parent].children.append(id)
        }
        for id in result.nodes.indices where result.nodes[id].isDirectory {
            result.nodes[id].modified = Date(timeIntervalSince1970: 1_699_999_000)
            result.nodes[id].created = Date(timeIntervalSince1970: 1_690_000_000)
            result.nodes[id].accessed = result.nodes[id].modified
        }
        aggregate(&result); result.folderCount = branches + 1; result.fileCount = files
        if branches > 1 { result.tags[result.nodes[1].path] = 1; result.nodes[2].nativeAttributes = 2 }
        return result
    }
    public static func aggregate(_ snapshot: inout ScanSnapshot) {
        for id in snapshot.nodes.indices where snapshot.nodes[id].isDirectory { snapshot.nodes[id].logicalBytes = 0; snapshot.nodes[id].allocatedBytes = 0 }
        if snapshot.nodes.count > 1 {
            for id in stride(from: snapshot.nodes.count - 1, through: 1, by: -1) {
                if let parent = snapshot.nodes[id].parent { snapshot.nodes[parent].logicalBytes += snapshot.nodes[id].logicalBytes; snapshot.nodes[parent].allocatedBytes += snapshot.nodes[id].allocatedBytes }
            }
        }
    }
    public static func disk(at root: URL, branches: Int = 8) throws {
        let manager = FileManager.default
        for index in 0..<branches {
            let dir = root.appendingPathComponent("branch-\(index)")
            try manager.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, size) in [("zero.bin",0),("boundary.bin",1024),("café.txt",1025),("UPPER.BIN",4096)] {
                let file = dir.appendingPathComponent(name); try Data(repeating: UInt8(index % 251), count: size).write(to: file)
                try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_699_999_000)], ofItemAtPath: file.path)
            }
        }
        let hidden = root.appendingPathComponent(".hidden")
        try manager.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data([1]).write(to: hidden.appendingPathComponent("child.bin"))
        try manager.linkItem(at: root.appendingPathComponent("branch-0/boundary.bin"), to: root.appendingPathComponent("alias.bin"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
    }
}
