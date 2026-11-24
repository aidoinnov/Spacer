import Foundation
import Darwin

/// Immutable per-operation scope. Inventory is a hint; observed device changes
/// fail closed. The system/Data firmlink view is allowed, its direct alias isn't.
struct ScanVolumePolicy: Sendable {
    struct Mount: Sendable { let path: String; let isLocalAPFS: Bool }
    struct DeviceRule: Sendable {
        let primary: dev_t
        let additional: dev_t?
        @inline(__always) func excludes(_ device: dev_t) -> Bool { device != primary && device != additional }
    }
    let traversal: ScanVolumeTraversal
    let anchor: String
    let deviceRule: DeviceRule?
    let mountRoots: Set<String>
    let inventoryComplete: Bool

    // getfsstat returns filled records; a completely full buffer cannot prove
    // that no further mount was omitted during the count/fill race.
    static func hasCompleteInventory(returned: Int32, capacity: Int) -> Bool {
        returned >= 0 && Int(returned) < capacity
    }

    init(traversal: ScanVolumeTraversal, anchor: String, device: dev_t,
         mounts: [Mount], dataDevice: dev_t? = nil, inventoryComplete: Bool = true) {
        self.traversal = traversal; self.anchor = anchor
        self.inventoryComplete = inventoryComplete
        var additional: dev_t?
        if anchor == "/", mounts.contains(where: { $0.path == "/" && $0.isLocalAPFS }),
           mounts.contains(where: { $0.path == "/System/Volumes/Data" && $0.isLocalAPFS }), let dataDevice {
            additional = dataDevice
        }
        deviceRule = traversal == .selectedVolume ? DeviceRule(primary: device, additional: additional) : nil
        mountRoots = Set(mounts.map(\.path).filter { $0 != anchor && SnapshotTree.contains(anchor, $0) })
    }

    func exclusion(path: String, device: dev_t, isScanRoot: Bool = false) -> String? {
        boundaryExclusion(path: path, isScanRoot: isScanRoot) ?? deviceExclusion(device)
    }

    func deviceExclusion(_ device: dev_t) -> String? {
        deviceRule?.excludes(device) == true ? "different_device" : nil
    }

    func boundaryExclusion(path: String, isScanRoot: Bool = false) -> String? {
        if isScanRoot, !SnapshotTree.contains(anchor, path) { return "outside_scope_root" }
        let dataPath = "/System/Volumes/Data"
        if anchor == "/", mountRoots.contains(dataPath),
           path == dataPath || (isScanRoot && SnapshotTree.contains(dataPath, path)) {
            return "duplicate_data_view"
        }
        guard traversal == .selectedVolume else { return nil }
        if mountRoots.contains(path) || (isScanRoot && mountRoots.contains { SnapshotTree.contains($0, path) }) {
            return path == "/System/Volumes/Data" ? "duplicate_data_view" : "mounted_volume"
        }
        return nil
    }

    static func discover(traversal: ScanVolumeTraversal, anchor: String, device: dev_t) -> Self {
        guard traversal == .selectedVolume || anchor == "/" else {
            return Self(traversal: traversal, anchor: anchor, device: device, mounts: [])
        }
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        var mounts: [Mount] = []
        var complete = false
        if count >= 0, count < 4096 {
            var values: [statfs] = Array(repeating: statfs(), count: Int(count) + 16)
            let found = values.withUnsafeMutableBufferPointer {
                getfsstat($0.baseAddress, Int32($0.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
            }
            if found >= 0 {
                complete = hasCompleteInventory(returned: found, capacity: values.count)
                for var value in values.prefix(min(Int(found), values.count)) {
                    let path = withUnsafeBytes(of: &value.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                    let type = withUnsafeBytes(of: &value.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                    let localAPFS = type == "apfs" && value.f_flags & UInt32(MNT_LOCAL) != 0
                    mounts.append(Mount(path: path, isLocalAPFS: localAPFS))
                    // Foundation may standardize /private/tmp to /tmp (also
                    // var/etc). Add lexical aliases without probing a remote
                    // mount merely to normalize its name.
                    for prefix in ["/private/tmp", "/private/var", "/private/etc"] where SnapshotTree.contains(prefix, path) {
                        mounts.append(Mount(path: String(prefix.dropFirst(8)) + path.dropFirst(prefix.count), isLocalAPFS: localAPFS))
                    }
                }
            }
        }
        var data = stat()
        let dataDevice = anchor == "/" && lstat("/System/Volumes/Data", &data) == 0 ? data.st_dev : nil
        return Self(traversal: traversal, anchor: anchor, device: device, mounts: mounts, dataDevice: dataDevice, inventoryComplete: complete)
    }
}
