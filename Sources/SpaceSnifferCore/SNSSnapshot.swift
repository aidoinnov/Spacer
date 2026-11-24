import Foundation

/// Native SNS record format, reconstructed from:
/// exportHardCoded 0x408a80, group-end 0x408a10, importHardCoded 0x408ef0,
/// importHardCoded_internal 0x4093c0, TBase64::encode 0x435410, exportNode 0x416650.
/// This is a binary record stream, not a renamed JSON file.
public enum SNSSnapshot {
    public struct RootInfo: Sendable {
        public let index: Int
        public let path: String
        public let files: Int
        public let folders: Int
        public let logicalBytes: Int64
        public let allocatedBytes: Int64
    }
    public static func inspectRoots(_ data: Data, legacyCodePage: UInt32? = nil, control: ScanControl? = nil) throws -> [RootInfo] {
        try decodeAll(data, legacyCodePage: legacyCodePage, control: control).enumerated().map { index, snapshot in
            RootInfo(index: index, path: snapshot.rootPath, files: snapshot.fileCount, folders: snapshot.folderCount,
                     logicalBytes: snapshot.nodes[0].logicalBytes, allocatedBytes: snapshot.nodes[0].allocatedBytes)
        }
    }
    public enum FormatError: LocalizedError {
        case malformed, unsupportedVersion(UInt8), invalidName, legacyCodePageRequired, unsupportedCodePage(UInt32), rootSelectionRequired(Int), invalidRootIndex
        public var errorDescription: String? {
            switch self {
            case .malformed: "SNS 스냅샷이 잘렸거나 구조가 잘못되었습니다."
            case let .unsupportedVersion(v): "SNS 인코딩 버전 \(v)은 지원하지 않습니다. 버전 1~4를 지원합니다."
            case .invalidName: "SNS 경로 이름을 읽거나 기록할 수 없습니다."
            case .legacyCodePageRequired: "SNS v2의 이름을 읽으려면 저장한 Windows의 ANSI 코드 페이지를 지정해야 합니다."
            case let .unsupportedCodePage(page): "이 환경에서 Windows 코드 페이지 \(page)을 읽을 수 없습니다."
            case let .rootSelectionRequired(count): "이 SNS에는 루트가 \(count)개 있습니다. 열 루트를 선택하세요."
            case .invalidRootIndex: "선택한 SNS 루트가 없습니다."
            }
        }
    }
    public static func encode(_ snapshot: ScanSnapshot, ids: Set<Int>? = nil, root: Int = 0) throws -> Data {
        var sink = ArtifactDataSink()
        try write(snapshot, ids: ids, root: root, to: &sink)
        return sink.value
    }
    /// Native TSNSSnapshotSnifAgent (0x4576f0) repeatedly imports top-level records.
    /// Keep each tree's original absolute path; window/root selection is a UI adapter.
    public static func encode(roots: [ScanSnapshot]) throws -> Data {
        guard !roots.isEmpty else { throw FormatError.malformed }
        var sink = ArtifactDataSink()
        for snapshot in roots { try write(snapshot.validated(), to: &sink) }
        return sink.value
    }
    public static func write<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, ids: Set<Int>? = nil, root: Int = 0, to sink: inout S) throws {
        try emit(snapshot, root: root, includes: { ids?.contains($0) ?? true }, to: &sink)
    }
    static func write<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, selected: [Bool], root: Int, to sink: inout S) throws {
        guard selected.count == snapshot.nodes.count else { throw FormatError.malformed }
        try emit(snapshot, root: root, includes: { selected[$0] }, to: &sink)
    }
    private static func emit<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, root: Int, includes: (Int) -> Bool, to sink: inout S) throws {
        guard snapshot.nodes.indices.contains(root) else { throw FormatError.malformed }
        func date(_ value: Date?) -> UInt64 {
            guard let value else { return 0 }
            let ticks = (value.timeIntervalSince1970 + 11_644_473_600) * 10_000_000
            return ticks > 0 && ticks < Double(UInt64.max) ? UInt64(ticks) : 0
        }
        var stack: [(Int, Bool)] = [(root, false)]
        while !stack.isEmpty {
          // A CLI or long-running native I/O lane has no per-event AppKit pool.
          // Bound Foundation's temporary UTF16/Base64 bridges across large exports.
          // The sink and immutable snapshot remain owned outside this pool.
          try autoreleasepool {
           for _ in 0..<1024 {
            guard let (id, end) = stack.popLast() else { break }
            if end { try sink.integer(UInt16(1)); continue }
            guard id == root || includes(id) else { continue }
            let n = snapshot.nodes[id]
            let type: UInt8 = n.nativeType ?? (id == root && snapshot.isVolumeRoot ? 1 : n.isDirectory ? 3 : 2)
            let name = id == root ? n.path : n.name
            guard let utf16 = name.data(using: .utf16LittleEndian) else { throw FormatError.invalidName }
            let encoded = utf16.base64EncodedData()
            // Native writer truncates at 8192. Rejecting avoids silently changing a selected macOS filename.
            guard !encoded.isEmpty, encoded.count <= 8192 else { throw FormatError.invalidName }
            try sink.integer(UInt8(4)); try sink.integer(type); try sink.integer(UInt32(encoded.count)); try sink.data(encoded)
            // Native drive export (0x408a80) writes getDriveSize to BOTH wire
            // fields; the treemap wrapper (0x46bb70) delegates without rewriting.
            // Keep unknown/nested stored records as supplied: this model has OS
            // capacity metadata only for its own whole-volume root.
            let capacity = id == 0 && snapshot.isVolumeRoot && type == 1 && snapshot.volumeTotal > 0 ? snapshot.volumeTotal : nil
            try sink.integer(capacity ?? n.logicalBytes); try sink.integer(capacity ?? n.allocatedBytes)
            try sink.integer(n.nativeAttributes ?? (n.isDirectory ? UInt32(0x10) : 0))
            try sink.integer(date(n.created)); try sink.integer(date(n.accessed)); try sink.integer(date(n.modified))
            try sink.integer(UInt8(snapshot.tags[n.path] ?? 0)); try sink.integer(n.nativeFlags ?? 0)
            stack.append((id, true))
            for child in n.children.reversed() { stack.append((child, false)) }
           }
          }
        }
    }
    public static func decode(_ data: Data, legacyCodePage: UInt32? = nil, rootIndex: Int? = nil, control: ScanControl? = nil) throws -> ScanSnapshot {
        let roots = try decodeAll(data, legacyCodePage: legacyCodePage, control: control)
        if let index = rootIndex {
            guard roots.indices.contains(index) else { throw FormatError.invalidRootIndex }
            return roots[index]
        }
        guard roots.count == 1 else { throw FormatError.rootSelectionRequired(roots.count) }
        return roots[0]
    }
    public static func decodeAll(_ data: Data, legacyCodePage: UInt32? = nil, control: ScanControl? = nil) throws -> [ScanSnapshot] {
        func checkCancellation() throws { if Task.isCancelled || control?.isCancelled == true { throw CancellationError() } }
        try checkCancellation()
        var offset = 0
        func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let count = MemoryLayout<T>.size
            guard count <= data.count - offset else { throw FormatError.malformed }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
            offset += count; return T(littleEndian: value)
        }
        func timestamp(_ value: UInt64) -> Date? {
            value == 0 ? nil : Date(timeIntervalSince1970: Double(value) / 10_000_000 - 11_644_473_600)
        }
        var snapshot = ScanSnapshot(rootPath: "")
        var roots: [ScanSnapshot] = []
        var stack: [Int] = []
        while offset < data.count {
          try checkCancellation()
          try autoreleasepool {
           for _ in 0..<1024 {
            guard offset < data.count else { break }
            let version = try read(UInt8.self)
            guard (1...4).contains(version) else { throw FormatError.unsupportedVersion(version) }
            let type = try read(UInt8.self)
            if type == 0 {
                guard !stack.isEmpty else { throw FormatError.malformed }
                stack.removeLast()
                if stack.isEmpty {
                    snapshot.finished = Date()
                    roots.append(try snapshot.validated(control: control))
                    snapshot = ScanSnapshot(rootPath: "")
                }
                continue
            }
            guard (1...6).contains(type), !snapshot.nodes.isEmpty || stack.isEmpty,
                  snapshot.nodes.isEmpty || !stack.isEmpty else { throw FormatError.malformed }
            let length = try read(UInt32.self)
            guard length > 0, length <= 8192, Int(length) <= data.count - offset else { throw FormatError.invalidName }
            let raw = data.subdata(in: offset..<(offset + Int(length))); offset += Int(length)
            let segment: String
            if version == 1 {
                guard let text = String(data: raw, encoding: .utf8) else { throw FormatError.invalidName }; segment = text
            } else if version == 2 {
                // 0x4093c0 -> decodeLegacy 0x436390/0x435f40 -> TStringStream
                // 0x684690 GetANSI and 0x684c70 GetDataString. The file does not
                // contain its original Windows ACP; never guess it from this Mac.
                let whitespace: Set<UInt8> = [9, 10, 13, 32]
                let encoded = raw.filter { !whitespace.contains($0) }
                guard let decoded = Data(base64Encoded: Data(encoded)) else { throw FormatError.invalidName }
                do { segment = try WindowsLegacyText.decode(decoded, codePage: legacyCodePage) }
                catch WindowsLegacyText.DecodeError.codePageRequired { throw FormatError.legacyCodePageRequired }
                catch let WindowsLegacyText.DecodeError.unsupportedCodePage(page) { throw FormatError.unsupportedCodePage(page) }
                catch { throw FormatError.invalidName }
            } else {
                guard let decoded = Data(base64Encoded: raw), decoded.count % 2 == 0,
                      let text = String(data: decoded, encoding: .utf16LittleEndian) else { throw FormatError.invalidName }
                segment = text
            }
            guard !segment.isEmpty, !segment.contains("\0") else { throw FormatError.invalidName }
            let logical = try read(Int64.self)
            let allocated: Int64
            if version < 4 {
                let delta = try read(Int32.self); let sum = logical.addingReportingOverflow(Int64(delta))
                guard !sum.overflow else { throw FormatError.malformed }; allocated = sum.partialValue
            } else { allocated = try read(Int64.self) }
            let attrs = try read(UInt32.self)
            let created = timestamp(try read(UInt64.self)); let accessed = timestamp(try read(UInt64.self))
            let modified = timestamp(try read(UInt64.self))
            let tag = try read(UInt8.self); let flags = try read(UInt8.self)
            guard logical >= 0, allocated >= 0, tag <= 15 else { throw FormatError.malformed }
            let id = snapshot.nodes.count; let parent = stack.last
            if let parent {
                guard snapshot.nodes[parent].isDirectory else { throw FormatError.malformed }
                if type == 4 || type == 5 { guard snapshot.nodes[parent].nativeType == 1 else { throw FormatError.malformed } }
            }
            let path: String
            if let parent { path = SnapshotPath.join(snapshot.nodes[parent].path, segment) }
            else { guard SnapshotPath.isAbsolute(segment) else { throw FormatError.invalidName }; path = segment; snapshot.rootPath = segment }
            var node = DiskNode(id: id, parent: parent, path: path,
                name: parent == nil ? SnapshotPath.displayName(segment) : segment, isDirectory: type == 1 || type == 3,
                logicalBytes: logical, allocatedBytes: allocated, modified: modified ?? .distantPast)
            node.created = created; node.accessed = accessed; node.nativeAttributes = attrs; node.nativeFlags = flags; node.nativeType = type
            node.ownAllocatedBytes = node.isDirectory ? 0 : allocated
            snapshot.nodes.append(node)
            if let parent { snapshot.nodes[parent].children.append(id) }
            if node.isDirectory { snapshot.folderCount += 1 } else if type == 2 { snapshot.fileCount += 1 }
            if tag != 0 { snapshot.tags[path] = Int(tag) }
            if type == 1 { snapshot.volumeTotal = logical; snapshot.isVolumeRoot = id == 0 }
            if type == 4 { snapshot.volumeFree += logical }
            stack.append(id)
           }
          }
        }
        guard stack.isEmpty, snapshot.nodes.isEmpty, !roots.isEmpty else { throw FormatError.malformed }
        try checkCancellation()
        return roots
    }
}
