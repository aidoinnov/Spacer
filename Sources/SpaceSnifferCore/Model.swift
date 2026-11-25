import Foundation

public enum SizeMode: String, Codable, CaseIterable, Sendable {
    case allocated, logical
    public var title: String { self == .allocated ? "디스크 사용량" : "파일 크기" }
}

public struct DiskNode: Codable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var parent: Int?
    @NodePathStorage public var path: String
    public var name: String
    public var isDirectory: Bool
    public var isSymbolicLink: Bool
    public var logicalBytes: Int64
    public var allocatedBytes: Int64
    private var optionalMetadata = NodeOptionalMetadata()
    public var created: Date? {
        get { optionalMetadata.created }
        set { optionalMetadata.created = newValue }
    }
    public var accessed: Date? {
        get { optionalMetadata.accessed }
        set { optionalMetadata.accessed = newValue }
    }
    public var nativeAttributes: UInt32? {
        get { optionalMetadata.nativeAttributes }
        set { optionalMetadata.nativeAttributes = newValue }
    }
    public var nativeFlags: UInt8? {
        get { optionalMetadata.nativeFlags }
        set { optionalMetadata.nativeFlags = newValue }
    }
    public var nativeType: UInt8? {
        get { optionalMetadata.nativeType }
        set { optionalMetadata.nativeType = newValue }
    }
    public var modified: Date
    public var children: [Int]
    public var issue: String?
    @FileIdentity public var fileIdentity: String? = nil
    var fileIdentityKey: FileIdentity? { _fileIdentity.isPresent ? _fileIdentity : nil }
    public var ownAllocatedBytes: Int64? {
        get { optionalMetadata.ownAllocatedBytes }
        set { optionalMetadata.ownAllocatedBytes = newValue }
    }
    public func bytes(_ mode: SizeMode) -> Int64 { mode == .logical ? logicalBytes : allocatedBytes }
    mutating func setNativeFileIdentity(device: Int64, inode: UInt64) {
        _fileIdentity = FileIdentity(device: device, inode: inode)
    }
    public init(id: Int, parent: Int?, path: String, name: String, isDirectory: Bool = false,
                isSymbolicLink: Bool = false, logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0,
                modified: Date = .distantPast, children: [Int] = [], issue: String? = nil) {
        self.init(id: id, parent: parent, storedPath: NodePathStorage(wrappedValue: path), name: name,
                  isDirectory: isDirectory, isSymbolicLink: isSymbolicLink,
                  logicalBytes: logicalBytes, allocatedBytes: allocatedBytes,
                  modified: modified, children: children, issue: issue)
    }
    /// Native scans can construct the compact path directly, without first
    /// allocating and immediately discarding a full child path.
    init(id: Int, parent: Int?, storedPath: NodePathStorage, name: String, isDirectory: Bool = false,
         isSymbolicLink: Bool = false, logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0,
         modified: Date = .distantPast, children: [Int] = [], issue: String? = nil) {
        self.id = id; self.parent = parent; self._path = storedPath; self.name = name
        self.isDirectory = isDirectory; self.isSymbolicLink = isSymbolicLink
        self.logicalBytes = logicalBytes; self.allocatedBytes = allocatedBytes
        self.modified = modified; self.children = children; self.issue = issue
    }
}

public struct ScanSnapshot: Codable, Sendable {
    public var version = 1
    public var rootPath: String
    public var started: Date
    public var finished: Date?
    public var nodes: NodeTable
    public var fileCount: Int
    public var folderCount: Int
    public var issues: [String]
    public var issueCount: Int
    public var cancelled: Bool
    public var volumeTotal: Int64
    public var volumeFree: Int64
    public var isVolumeRoot: Bool
    public var tags: [String: Int]
    public var volumeCoverage: ScanVolumeCoverage?
    public init(rootPath: String, nodes: [DiskNode] = []) {
        self.rootPath = rootPath; self.started = Date(); self.nodes = NodeTable(nodes)
        self.fileCount = 0; self.folderCount = 0; self.issues = []; self.issueCount = 0
        self.cancelled = false; self.volumeTotal = 0; self.volumeFree = 0
        self.isVolumeRoot = false; self.tags = [:]
    }
    public func validated(control: ScanControl? = nil) throws -> Self {
        if control?.isCancelled == true { throw CancellationError() }
        guard version == 1, !nodes.isEmpty, nodes[0].parent == nil, nodes[0].path == rootPath,
              volumeTotal >= 0, volumeFree >= 0, fileCount >= 0, folderCount >= 0, issueCount >= 0 else { throw SnapshotError.invalid }
        for (index, mask) in tags.values.enumerated() {
            if index & 255 == 0, control?.isCancelled == true { throw CancellationError() }
            guard (1...15).contains(mask) else { throw SnapshotError.invalid }
        }
        if let coverage = volumeCoverage {
            guard coverage.exclusions.count <= 500, coverage.excludedCount >= coverage.exclusions.count,
                  Set(coverage.exclusions.map(\.path)).count == coverage.exclusions.count,
                  coverage.exclusions.allSatisfy({ SnapshotPath.isAbsolute($0.path) && SnapshotTree.contains(rootPath, $0.path) }) else { throw SnapshotError.invalid }
        }
        // IDs are already bounded by nodes.count. One bit per ID preserves Set
        // insertion/duplicate semantics without millions of hash table entries.
        // Avoid (count + 7), which could overflow before division.
        let byteCount = nodes.count / 8 + (nodes.count % 8 == 0 ? 0 : 1)
        var incoming = [UInt8](repeating: 0, count: byteCount)
        var incomingCount = 0
        var edgeCount = 0
        // Drive records store volume capacity, not the descendant aggregate.
        // Bound all leaf sums independently so filtering cannot overflow when
        // a drive's recorded capacity is smaller than clone/shared accounting.
        var leafLogical:Int64=0, leafAllocated:Int64=0
        for (i, node) in nodes.enumerated() {
            if i & 255 == 0, control?.isCancelled == true { throw CancellationError() }
            guard node.id == i, node.logicalBytes >= 0, node.allocatedBytes >= 0,
                  (node.ownAllocatedBytes ?? 0) >= 0, SnapshotPath.isAbsolute(node.path), node.children.count <= nodes.count else { throw SnapshotError.invalid }
            if i > 0 {
                guard let parent = node.parent, parent >= 0, parent < i else { throw SnapshotError.invalid }
                let expected = SnapshotPath.join(nodes[parent].path, node.name)
                guard node.name != ".", node.name != "..", !node.name.contains("/"), (!SnapshotPath.isWindows(nodes[parent].path) || !node.name.contains("\\")), node.path == expected else { throw SnapshotError.invalid }
            }
            var logicalSum: Int64 = 0; var allocatedSum: Int64 = 0
            for child in node.children {
                if edgeCount & 255 == 0, control?.isCancelled == true { throw CancellationError() }
                edgeCount += 1
                guard child > i, child < nodes.count, nodes[child].parent == i else { throw SnapshotError.invalid }
                let byte = child / 8; let mask = UInt8(1) << (child & 7)
                guard incoming[byte] & mask == 0 else { throw SnapshotError.invalid }
                incoming[byte] |= mask; incomingCount += 1
                let l = logicalSum.addingReportingOverflow(nodes[child].logicalBytes)
                let a = allocatedSum.addingReportingOverflow(nodes[child].allocatedBytes)
                guard !l.overflow, !a.overflow else { throw SnapshotError.invalid }
                logicalSum = l.partialValue; allocatedSum = a.partialValue
            }
            guard node.isDirectory || node.children.isEmpty else {throw SnapshotError.invalid}
            if node.nativeType != 1 {
                guard node.logicalBytes >= logicalSum, node.allocatedBytes >= allocatedSum else {throw SnapshotError.invalid}
            }
            if !node.isDirectory {
                let logical=leafLogical.addingReportingOverflow(node.logicalBytes)
                let allocated=leafAllocated.addingReportingOverflow(node.allocatedBytes)
                guard !logical.overflow, !allocated.overflow else {throw SnapshotError.invalid}
                leafLogical=logical.partialValue;leafAllocated=allocated.partialValue
            }
        }
        guard incomingCount == nodes.count - 1 else { throw SnapshotError.invalid }
        if control?.isCancelled == true { throw CancellationError() }
        return self
    }
}
public enum SnapshotError: Error { case invalid }

public enum FileCategory: String, CaseIterable, Sendable {
    case folder, image, video, audio, archive, code, document, other
    public var title: String {
        switch self {
        case .folder: "폴더"; case .image: "이미지"; case .video: "동영상"
        case .audio: "오디오"; case .archive: "압축·디스크"; case .code: "개발 파일"
        case .document: "문서"; case .other: "기타"
        }
    }
    public static func of(_ node: DiskNode) -> Self {
        if node.isDirectory { return .folder }
        switch URL(fileURLWithPath: node.name).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "svg", "raw": return .image
        case "mp4", "mov", "mkv", "avi", "webm", "m4v": return .video
        case "mp3", "m4a", "wav", "flac", "aiff", "ogg": return .audio
        case "zip", "7z", "rar", "gz", "tar", "dmg", "iso", "pkg", "xz": return .archive
        case "swift", "js", "ts", "tsx", "jsx", "py", "rs", "go", "c", "h", "cpp", "json", "html", "css": return .code
        case "pdf", "docx", "doc", "txt", "md", "xlsx", "pptx", "pages", "numbers": return .document
        default: return .other
        }
    }
}

public func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
