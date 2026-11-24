import Foundation
import SpaceSnifferCore

@main enum MakeMemorySnapshot {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: make-memory-snapshot output.sns") }
        let folders = 100, filesPerFolder = 2500
        var snapshot = ScanSnapshot(rootPath: "/MemoryQA")
        snapshot.nodes.append(DiskNode(id: 0, parent: nil, path: snapshot.rootPath, name: "MemoryQA", isDirectory: true,
            logicalBytes: Int64(folders * filesPerFolder), allocatedBytes: Int64(folders * filesPerFolder * 4096)))
        for folder in 0..<folders {
            let folderID = snapshot.nodes.count
            let path = "/MemoryQA/folder-\(folder)"
            snapshot.nodes[0].children.append(folderID)
            snapshot.nodes.append(DiskNode(id: folderID, parent: 0, path: path, name: "folder-\(folder)", isDirectory: true,
                logicalBytes: Int64(filesPerFolder), allocatedBytes: Int64(filesPerFolder * 4096)))
            for file in 0..<filesPerFolder {
                let id = snapshot.nodes.count
                snapshot.nodes[folderID].children.append(id)
                snapshot.nodes.append(DiskNode(id: id, parent: folderID, path: path + "/file-\(file).bin", name: "file-\(file).bin", logicalBytes: 1, allocatedBytes: 4096))
            }
        }
        snapshot.fileCount = folders * filesPerFolder; snapshot.folderCount = folders + 1
        _ = try snapshot.validated()
        try SNSSnapshot.encode(snapshot).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Created synthetic SNS: \(snapshot.fileCount) files / \(snapshot.folderCount) folders")
    }
}
