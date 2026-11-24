import Foundation
#if canImport(SpaceSnifferCore)
import SpaceSnifferCore
#else
import ExplorerDomain
#endif
/// SSW1 is an IPC schema, not a new SNS codec. Domain selection/encoding remain native.
enum WireBinary {
    private enum Failure:Error {case invalid}
    static func write(_ source:ScanSnapshot,to destination:URL,version:String?)throws {
        guard !source.nodes.isEmpty,source.nodes.count<=20_000_000 else {throw Failure.invalid}
        let temporary=destination.deletingLastPathComponent().appendingPathComponent(".wire-"+UUID().uuidString)
        guard FileManager.default.createFile(atPath:temporary.path,contents:nil) else {throw Failure.invalid}
        defer {try? FileManager.default.removeItem(at:temporary)}
        let file=try FileHandle(forWritingTo:temporary)
        do {
            var sink=Sink(file:file)
            try sink.data(Data("SSW1".utf8));try sink.integer(UInt16(2));try sink.string(version ?? "");try sink.integer(UInt32(source.nodes.count));try sink.string(source.rootPath)
            try sink.integer(UInt8((source.cancelled ? 1:0)|(source.isVolumeRoot ? 2:0)))
            try sink.integer(UInt8(source.volumeCoverage.map {$0.traversal == .allVolumes ? 2:1} ?? 0))
            for count in [source.fileCount,source.folderCount,source.issueCount,source.volumeCoverage?.excludedCount ?? 0] {guard count>=0 else {throw Failure.invalid};try sink.integer(UInt64(count))}
            try sink.double((source.finished ?? Date()).timeIntervalSince(source.started))
            for count in [source.volumeTotal,source.volumeFree] {guard count>=0 else {throw Failure.invalid};try sink.integer(UInt64(count))}
            try sink.integer(UInt32(min(500,source.issues.count)))
            for issue in source.issues.prefix(500) {try sink.string(issue)}
            guard source.tags.count<=20_000_000 else {throw Failure.invalid};try sink.integer(UInt32(source.tags.count))
            for (path,mask) in source.tags {guard (1...15).contains(mask) else {throw Failure.invalid};try sink.string(path);try sink.integer(UInt8(mask))}
            for (id,node) in source.nodes.enumerated() {
                guard node.id==id,node.logicalBytes>=0,node.allocatedBytes>=0,node.children.count<=source.nodes.count else {throw Failure.invalid}
                try sink.integer(Int64(node.parent ?? -1));try sink.string(node.name)
                try sink.integer(UInt64(node.logicalBytes));try sink.integer(UInt64(node.allocatedBytes))
                try sink.integer(node.nativeAttributes ?? (node.name.hasPrefix(".") ? 2:0))
                let flags:UInt8=(node.isDirectory ? 1:0)|(node.isSymbolicLink ? 2:0)|(node.created != nil ? 4:0)|(node.accessed != nil ? 8:0)|(node.nativeType != nil ? 16:0)|(node.nativeFlags != nil ? 32:0)
                try sink.integer(flags);try sink.double(node.modified.timeIntervalSince1970)
                try sink.double(node.created?.timeIntervalSince1970 ?? 0);try sink.double(node.accessed?.timeIntervalSince1970 ?? 0)
                try sink.integer(node.nativeType ?? 0);try sink.integer(node.nativeFlags ?? 0)
                if let issue=node.issue {try sink.string(issue)}else{try sink.integer(UInt32.max)}
                try sink.integer(UInt32(node.children.count))
                for child in node.children {guard child>=0,child<source.nodes.count else {throw Failure.invalid};try sink.integer(UInt32(child))}
            }
            try sink.flush();try file.synchronize();try file.close();try WirePublication.publish(temporary,to:destination)
        }catch {try? file.close();throw error}
    }
    private struct Sink {
        let file:FileHandle
        var buffer=Data()
        mutating func data(_ data:Data)throws {
            var offset=0
            while offset<data.count {let count=min(65536-buffer.count,data.count-offset);buffer.append(data[offset..<offset+count]);offset+=count;if buffer.count==65536 {try flush()}}
        }
        mutating func integer<T:FixedWidthInteger>(_ number:T)throws {var value=number.littleEndian;try withUnsafeBytes(of:&value){try data(Data($0))}}
        mutating func double(_ value:Double)throws {guard value.isFinite else {throw Failure.invalid};try integer(value.bitPattern)}
        mutating func string(_ value:String)throws {let bytes=Data(value.utf8);guard bytes.count<Int(UInt32.max) else {throw Failure.invalid};try integer(UInt32(bytes.count));try data(bytes)}
        mutating func flush()throws {guard !buffer.isEmpty else{return};try file.write(contentsOf:buffer);buffer.removeAll(keepingCapacity:true)}
    }
}
func writeWireSnapshot(_ snapshot:ScanSnapshot,to output:URL,binary:Bool,version:String? = nil)throws {
    if binary {try WireBinary.write(snapshot,to:output,version:version)}else{try JSONEncoder().encode(WireSnapshot(snapshot,version:version)).write(to:output,options:.atomic)}
}

func usesBinaryWire(_ args:[String])->Bool {guard let index=args.firstIndex(of:"--wire"),args.indices.contains(index+1) else{return false};return args[index+1]=="binary"}
