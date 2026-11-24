import Foundation
#if canImport(SpaceSnifferCore)
import SpaceSnifferCore
#else
import ExplorerDomain
#endif

/// One serialized document lane. Commands identify the immutable source they saw.
/// Output chunks are bounded; the UI owns destination creation and atomic publication.
final class DocumentService: @unchecked Sendable {
    private let lock = NSLock()
    private let queries=SubtreeQuerySession()
    private var queryContext:QueryContext?
    private var queryKey:String?
    private var queryFilter:String?
    private var versions: [(String, ScanSnapshot)] = []
    /// Register the immutable source before its file becomes visible; prune only
    /// after successful publication. Failed writes preserve the prior two leases.
    func publish(_ snapshot:ScanSnapshot,to output:URL,binary:Bool)throws->String {
        let version=UUID().uuidString
        lock.lock();versions.append((version,snapshot));lock.unlock()
        do {try writeWireSnapshot(snapshot,to:output,binary:binary,version:version)}
        catch {lock.lock();versions.removeAll {$0.0==version};lock.unlock();throw error}
        lock.lock();queryContext=nil;queryKey=nil;queryFilter=nil;queries.reset()
        if versions.count>2 {versions.removeFirst(versions.count-2)}
        lock.unlock();return version
    }
    func handle(_ line: String) -> Bool {
        guard let data = line.data(using: .utf8), let command = try? JSONDecoder().decode(DocumentCommand.self, from: data) else { return false }
        do {
            if command.operation == "exportConfigurations" {
                var sink=DocumentSink(request:command.request)
                let rows=try Self.configurationRows(command)
                try JSONEncoder().encode(rows).withUnsafeBytes {try sink.append($0)}
                sink.flush();bridgeEmit(DocumentReply(type:"documentEnd",request:command.request,bytes:sink.count));return true
            }
            lock.lock()
            let found = versions.first { $0.0 == command.version }?.1
            lock.unlock()
            guard var snapshot = found else { throw DocumentError.expired }
            if let tags = command.tags {
                guard tags.values.allSatisfy({ (1...15).contains($0) }) else { throw SnapshotError.invalid }
                snapshot.tags = tags
            }
            let mode: SizeMode = command.logical == true ? .logical : .allocated
            var sink = DocumentSink(request: command.request)
            if command.operation == "query" {
                let filter=try ScanFilter(command.filter ?? "")
                // request IDs vary; context reuse is keyed by explicit immutable view revision.
                let revision=command.queryRevision ?? command.version
                let cacheKey=command.version+":"+revision+":"+String(command.root ?? 0)
                guard snapshot.nodes.indices.contains(command.root ?? 0) else {throw SnapshotError.invalid}
                let context:QueryContext
                lock.lock()
                let cachedContext=queryContext;let cachedKey=queryKey;let cachedFilter=queryFilter
                lock.unlock()
                if let cached=cachedContext,cachedKey==cacheKey, cached.snapshot.tags==snapshot.tags,
                   cached.mode==mode,cached.showHidden==(command.hidden ?? true),cachedFilter == (command.filter ?? "") {
                    context=cached
                } else {
                    let weights=filter.weights(in:snapshot,mode:mode,showHidden:command.hidden ?? true)
                    context=QueryContext(snapshot:snapshot,weights:weights,filter:filter,mode:mode,showHidden:command.hidden ?? true,revision:revision,focus:command.root ?? 0,selection:nil)
                    lock.lock()
                    if versions.contains(where:{$0.0==command.version}) {queryContext=context;queryKey=cacheKey;queryFilter=command.filter ?? ""}
                    lock.unlock()
                }
                let arguments=command.arguments ?? [:]
                let result:JSONValue
                if command.query == "query_nodes",arguments["traversal"]?.string == "subtree" { result=try queries.query(context:context,arguments:arguments) }
                else { result=try context.query(command:command.query ?? "",arguments:arguments) }
                try JSONEncoder().encode(result).withUnsafeBytes {try sink.append($0)}
            } else if command.operation == "configuredReport" {
                let xml=try Self.configurationData(command)
                let maximum=command.maxOutputBytes ?? 1_073_741_824
                guard (1...1_073_741_824).contains(maximum) else {throw SnapshotError.invalid}
                try ExplorerSemantics.configuredReport(snapshot,xml:xml,index:command.configurationIndex ?? 0,
                    text:command.filter ?? "",mode:mode,hidden:command.hidden ?? true,root:command.root ?? 0,codePage:command.codePage,maximumOutputBytes:maximum,to:&sink)
            } else if command.operation == "weights" {
                let weights = try ExplorerSemantics.weights(snapshot, text: command.filter ?? "", mode: mode, hidden: command.hidden ?? true)
                for value in weights {
                    var little = UInt64(value).littleEndian
                    try withUnsafeBytes(of: &little) { try sink.append($0) }
                }
            } else if command.operation == "sns" || command.operation == "report" {
                try ExplorerSemantics.write(snapshot, text: command.filter ?? "", mode: mode, hidden: command.hidden ?? true,
                    root: command.root ?? 0, report: command.operation == "report", to: &sink)
            } else { throw DocumentError.operation }
            sink.flush()
            bridgeEmit(DocumentReply(type: "documentEnd", request: command.request, bytes: sink.count))
        } catch {
            bridgeEmit(DocumentReply(type: "documentError", request: command.request, message: error.localizedDescription))
        }
        return true
    }
    private static func configurationData(_ command:DocumentCommand)throws->Data {
        guard let encoded=command.configuration,encoded.utf8.count<=5_592_408,let xml=Data(base64Encoded:encoded),xml.count<=4_194_304 else {throw SnapshotError.invalid}
        return xml
    }
    private static func configurationRows(_ command:DocumentCommand)throws->[[String:JSONValue]] {
        let configs=try ExplorerSemantics.exportConfigurations(configurationData(command),codePage:command.codePage)
        return configs.enumerated().map {index,config in ["index":.int(index),"description":.string(config.description),"filename":.string(config.preferredFileName),"extension":.string(config.preferredFileExtension),"header":.string(config.headerFormat),"detail":.string(config.detailFormat),"footer":.string(config.footerFormat),"block_sorting":.string(config.blockSorting),"fine_sorting":.string(config.fineSorting),"direction":.string(config.fineSortingDirection)]}
    }

}
private enum DocumentError: LocalizedError {
    case expired, operation
    var errorDescription: String? { self == .expired ? "스냅샷이 갱신됐습니다. 최신 결과에서 다시 시도하세요." : "지원하지 않는 문서 작업입니다." }
}
private struct DocumentCommand: Codable {
    var request: String; var operation: String; var version: String
    var maxOutputBytes:Int64?;var query:String?;var queryRevision:String?;var arguments:[String:JSONValue]?
    var configuration:String?; var configurationIndex:Int?;var codePage:UInt32?
    var filter: String?; var logical: Bool?; var hidden: Bool?; var root: Int?; var tags: [String:Int]?
}
private struct DocumentReply: Encodable {
    var type: String; var request: String; var data: String?; var bytes: Int?; var message: String?
}
private struct DocumentSink: ArtifactByteSink {
    let request: String
    var buffer = Data()
    var count = 0
    mutating func append(_ bytes: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < bytes.count {
            let size = min(65_536-buffer.count, bytes.count-offset)
            buffer.append(contentsOf: bytes.bindMemory(to: UInt8.self)[offset..<offset+size]); offset += size; count += size
            if buffer.count == 65_536 { flush() }
        }
    }
    mutating func flush() {
        guard !buffer.isEmpty else { return }
        bridgeEmit(DocumentReply(type: "documentData", request: request, data: buffer.base64EncodedString()))
        buffer.removeAll(keepingCapacity: true)
    }
}
private let outputLock = NSLock()
func bridgeEmit<T: Encodable>(_ value: T) {
    guard let bytes = try? JSONEncoder().encode(value) else { return }
    outputLock.lock(); defer { outputLock.unlock() }
    FileHandle.standardOutput.write(bytes); FileHandle.standardOutput.write(Data([10]))
}

/// Codec-only owner for inspection before any scan or document has been opened.
func runDocumentService(_ args:[String])->Bool {
    guard args.count>1,args[1]=="--documents" else {return false}
    let service=DocumentService();bridgeEmit(["type":"documentReady"])
    while let line=readLine(),line != "quit" {_ = service.handle(line)}
    return true
}
