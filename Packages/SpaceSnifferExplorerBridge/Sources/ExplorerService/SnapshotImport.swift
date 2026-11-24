import Foundation
#if canImport(SpaceSnifferCore)
import SpaceSnifferCore
#else
import ExplorerDomain
#endif

/// Import selection never guesses a multi-root tree or a legacy Windows code page.
func runSnapshotImport(_ args: [String]) throws -> Bool {
    guard args.count >= 5, args[1] == "--open", args[3] == "--output" else { return false }
    let documents = DocumentService()
    let source = URL(fileURLWithPath: args[2]); let output = URL(fileURLWithPath: args[4])
    do {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        var roots: [ScanSnapshot] = []
        var page: UInt32?
        while roots.isEmpty {
            do {
                roots = try DUSnapshot.accepts(filename: source.lastPathComponent)
                    ? DUSnapshot.decodeAll(data, legacyCodePage: page) : SNSSnapshot.decodeAll(data, legacyCodePage: page)
            } catch SNSSnapshot.FormatError.legacyCodePageRequired {
                bridgeEmit(["type":"importCodePage"])
                guard let line = readLine(), line.hasPrefix("codepage "), let value = UInt32(line.dropFirst(9)) else { return true }
                page = value
            } catch WindowsLegacyText.DecodeError.codePageRequired {
                bridgeEmit(["type":"importCodePage"])
                guard let line = readLine(), line.hasPrefix("codepage "), let value = UInt32(line.dropFirst(9)) else { return true }
                page = value
            }
        }
        if args.contains("--inspect-only") {
            struct Root:Encodable {var index:Int;var path:String;var files:Int;var folders:Int;var logical_bytes:Int64;var allocated_bytes:Int64}
            struct Inspection:Encodable {let type="importInspection";var roots:[Root]}
            bridgeEmit(Inspection(roots:roots.enumerated().map {index,snapshot in Root(index:index,path:snapshot.rootPath,files:snapshot.fileCount,folders:snapshot.folderCount,logical_bytes:snapshot.nodes[0].logicalBytes,allocated_bytes:snapshot.nodes[0].allocatedBytes)}))
            return true
        }
        var index = 0
        if roots.count > 1 {
            struct Choices: Encodable { let type = "importRoots"; let roots: [String] }
            bridgeEmit(Choices(roots: roots.map {"\($0.rootPath) · \(formattedBytes($0.nodes[0].allocatedBytes))"}))
            guard let line = readLine(), line.hasPrefix("select "), let selected = Int(line.dropFirst(7)), roots.indices.contains(selected) else { return true }
            index = selected
        }
        let snapshot = roots[index]; roots.removeAll()
        let version=try documents.publish(snapshot,to:output,binary:usesBinaryWire(args))
        bridgeEmit(["type":"complete", "version":version, "output":output.path])
        while let line = readLine(), line != "quit" { _ = documents.handle(line) }
    } catch { bridgeEmit(["type":"failure", "message":error.localizedDescription]) }
    return true
}
