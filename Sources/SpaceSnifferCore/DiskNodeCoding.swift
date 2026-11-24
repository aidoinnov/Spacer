import Foundation

/// The wire schema remains the public node fields, not its compact storage.
extension DiskNode {
    private enum CodingKeys: String, CodingKey {
        case id, parent, path, name, isDirectory, isSymbolicLink, logicalBytes, allocatedBytes
        case created, accessed, nativeAttributes, nativeFlags, nativeType, modified, children, issue, fileIdentity, ownAllocatedBytes
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(Int.self, forKey: .id), parent: try c.decodeIfPresent(Int.self, forKey: .parent),
            path: try c.decode(String.self, forKey: .path), name: try c.decode(String.self, forKey: .name),
            isDirectory: try c.decode(Bool.self, forKey: .isDirectory), isSymbolicLink: try c.decode(Bool.self, forKey: .isSymbolicLink),
            logicalBytes: try c.decode(Int64.self, forKey: .logicalBytes), allocatedBytes: try c.decode(Int64.self, forKey: .allocatedBytes),
            modified: try c.decode(Date.self, forKey: .modified), children: try c.decode([Int].self, forKey: .children),
            issue: try c.decodeIfPresent(String.self, forKey: .issue))
        created = try c.decodeIfPresent(Date.self, forKey: .created)
        accessed = try c.decodeIfPresent(Date.self, forKey: .accessed)
        nativeAttributes = try c.decodeIfPresent(UInt32.self, forKey: .nativeAttributes)
        nativeFlags = try c.decodeIfPresent(UInt8.self, forKey: .nativeFlags)
        nativeType = try c.decodeIfPresent(UInt8.self, forKey: .nativeType)
        fileIdentity = try c.decodeIfPresent(String.self, forKey: .fileIdentity)
        ownAllocatedBytes = try c.decodeIfPresent(Int64.self, forKey: .ownAllocatedBytes)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encodeIfPresent(parent, forKey: .parent)
        try c.encode(path, forKey: .path); try c.encode(name, forKey: .name)
        try c.encode(isDirectory, forKey: .isDirectory); try c.encode(isSymbolicLink, forKey: .isSymbolicLink)
        try c.encode(logicalBytes, forKey: .logicalBytes); try c.encode(allocatedBytes, forKey: .allocatedBytes)
        try c.encodeIfPresent(created, forKey: .created); try c.encodeIfPresent(accessed, forKey: .accessed)
        try c.encodeIfPresent(nativeAttributes, forKey: .nativeAttributes); try c.encodeIfPresent(nativeFlags, forKey: .nativeFlags)
        try c.encodeIfPresent(nativeType, forKey: .nativeType); try c.encode(modified, forKey: .modified)
        try c.encode(children, forKey: .children); try c.encodeIfPresent(issue, forKey: .issue)
        try c.encodeIfPresent(fileIdentity, forKey: .fileIdentity); try c.encodeIfPresent(ownAllocatedBytes, forKey: .ownAllocatedBytes)
    }
}
