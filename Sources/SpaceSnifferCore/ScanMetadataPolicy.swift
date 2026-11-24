import Darwin

/// Per-run I/O choice, cached by observed device. Traversal scope is unchanged.
/// Unknown/remote filesystems retain POSIX; a new mounted device is probed once.
struct ScanMetadataPolicy {
    private var decisions: [dev_t: Bool] = [:]

    static func allowsBulk(filesystem: String, isLocal: Bool) -> Bool {
        isLocal && filesystem == "apfs"
    }

    mutating func allowsBulk(path: String, device: dev_t) -> Bool {
        if let decision = decisions[device] { return decision }
        var volume = statfs()
        let decision: Bool
        if statfs(path, &volume) == 0 {
            let filesystem = withUnsafeBytes(of: &volume.f_fstypename) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            decision = Self.allowsBulk(filesystem: filesystem, isLocal: volume.f_flags & UInt32(MNT_LOCAL) != 0)
        } else { decision = false }
        decisions[device] = decision
        return decision
    }
}
