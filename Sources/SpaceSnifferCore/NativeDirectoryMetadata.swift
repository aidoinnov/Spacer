import Foundation
import Darwin
import SpaceSnifferScanEngine

/// Only fields actually consumed by DiskScanner; this is not a fabricated stat.
struct NativeFileMetadata: Sendable {
    let isDirectory: Bool, isSymbolicLink: Bool, isRegular: Bool
    let device: dev_t, inode: ino_t
    let logicalBytes: Int64, allocatedBytes: Int64
    let createdSeconds: Int64, accessedSeconds: Int64, modifiedSeconds: Int64
    let permissions: UInt32, flags: UInt32

    init(_ value: stat) {
        let type = value.st_mode & S_IFMT
        isDirectory = type == S_IFDIR; isSymbolicLink = type == S_IFLNK; isRegular = type == S_IFREG
        device = value.st_dev; inode = value.st_ino
        logicalBytes = isRegular ? max(0, value.st_size) : 0
        allocatedBytes = isRegular ? max(0, Int64(value.st_blocks) * 512) : 0
        createdSeconds = Int64(value.st_birthtimespec.tv_sec); accessedSeconds = Int64(value.st_atimespec.tv_sec)
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        permissions = UInt32(value.st_mode & 0o7777); flags = value.st_flags
    }

    fileprivate init(type: fsobj_type_t, device: dev_t, inode: UInt64, logical: Int64, allocated: Int64,
                     created: timespec, accessed: timespec, modified: timespec, permissions: UInt32, flags: UInt32) {
        isDirectory = type == VDIR.rawValue; isSymbolicLink = type == VLNK.rawValue; isRegular = type == VREG.rawValue
        self.device = device; self.inode = inode; logicalBytes = isRegular ? logical : 0; allocatedBytes = isRegular ? allocated : 0
        createdSeconds = Int64(created.tv_sec); accessedSeconds = Int64(accessed.tv_sec); modifiedSeconds = Int64(modified.tv_sec)
        self.permissions = permissions & 0o7777; self.flags = flags
    }
}

/// Mac platform I/O candidate inspired by W17/W23 metadata reuse. A private fd
/// keeps the legacy readdir cursor untouched. The default read exhausts the
/// bounded directory; census candidates require independent namespace proof; stream() validates each batch before
/// delivery and requires the caller to deduplicate on later fallback.
struct NativeDirectoryMetadata: Sendable {
    typealias Entry = DirectoryEntry<NativeFileMetadata>
    typealias CountCall = @Sendable (String, inout attrlist, UnsafeMutableRawPointer, Int, UInt32) -> Int32
    typealias BulkCall = @Sendable (Int32, inout attrlist, UnsafeMutableRawPointer, Int, UInt64) -> Int32
    let minimumEntries: Int, maximumEntries: Int, maximumEstimatedBytes: Int
    private let call: BulkCall
    private let countCall: CountCall
    private static let bufferBytes = 64 * 1024
    private static let requiredCommon = UInt32(ATTR_CMN_NAME) | UInt32(ATTR_CMN_DEVID) | UInt32(ATTR_CMN_OBJTYPE) |
        UInt32(ATTR_CMN_CRTIME) | UInt32(ATTR_CMN_MODTIME) | UInt32(ATTR_CMN_ACCTIME) |
        UInt32(ATTR_CMN_ACCESSMASK) | UInt32(ATTR_CMN_FLAGS) | UInt32(ATTR_CMN_FILEID)
    private static let requiredFile = UInt32(ATTR_FILE_ALLOCSIZE) | UInt32(ATTR_FILE_DATALENGTH)

    static var orderedScan: Self {
        // The byte preflight remains 32 MiB. A larger count ceiling lets a
        // short-name directory just beyond 131072 use that existing budget;
        // metadata ordering no longer needs a second full entry array.
        Self(maximumEntries: 262_144, maximumEstimatedBytes: 32 * 1024 * 1024, minimumEntries: 16)
    }

    func boundedForReadAhead() -> Self {
        let entries = min(maximumEntries, 2048)
        return Self(maximumEntries: entries, maximumEstimatedBytes: min(maximumEstimatedBytes, 512 * 1024),
                    minimumEntries: 0, countCall: countCall, call: call)
    }

    private static func entryCharge(nameBytes: Int) -> Int {
        MemoryLayout<Entry>.stride + nameBytes + 128
    }

    init(maximumEntries: Int = 4096, maximumEstimatedBytes: Int = 4 * 1024 * 1024,
         minimumEntries: Int = 0,
         countCall: @escaping CountCall = { path, attrs, buffer, count, options in
             getattrlist(path, &attrs, buffer, count, options)
         }, call: @escaping BulkCall = { fd, attrs, buffer, count, options in
             getattrlistbulk(fd, &attrs, buffer, count, options)
         }) {
        precondition(maximumEntries > 0 && maximumEstimatedBytes > 0 && minimumEntries >= 0 && minimumEntries <= maximumEntries)
        self.minimumEntries = minimumEntries; self.maximumEntries = maximumEntries
        self.maximumEstimatedBytes = maximumEstimatedBytes; self.call = call; self.countCall = countCall
    }

    /// A race-prone I/O selection hint, never an authoritative child count.
    /// SDK warns ENTRYCOUNT can be expensive on some volume formats.
    func entryCount(_ path: String, control: ScanControl,
                    observeQuery: (EntryCountObservation) -> Void = { _ in }) -> UInt32? {
        guard !control.isCancelled else { return nil }
        var attrs = attrlist(); attrs.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS); attrs.dirattr = UInt32(ATTR_DIR_ENTRYCOUNT)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 8)
        defer { storage.deallocate() }
        let started = DispatchTime.now().uptimeNanoseconds
        let status = countCall(path, &attrs, storage, 32, UInt32(FSOPT_PACK_INVAL_ATTRS | FSOPT_NOFOLLOW))
        let code: Int32? = status == 0 ? nil : errno // capture before clock or callbacks
        let elapsed = DispatchTime.now().uptimeNanoseconds &- started
        let cancelled = control.isCancelled
        let count = status == 0 && !cancelled ? Self.decodeEntryCount(storage) : nil
        observeQuery(EntryCountObservation(elapsedNanoseconds: elapsed, errorCode: code,
            unavailableResult: status == 0 && !cancelled && count == nil, cancelledAfterCall: cancelled))
        return count
    }

    private static func decodeEntryCount(_ storage: UnsafeRawPointer) -> UInt32? {
        let length = storage.loadUnaligned(as: UInt32.self)
        guard length >= 28, length <= 32 else { return nil }
        let returned = storage.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
        guard returned.dirattr & UInt32(ATTR_DIR_ENTRYCOUNT) != 0 else { return nil }
        return storage.loadUnaligned(fromByteOffset: 24, as: UInt32.self)
    }

    /// Batch delivery is opt-in. A malformed/later failed batch is never
    /// delivered. The caller must deduplicate already delivered names if it
    /// falls back to POSIX after a later failure. Unlike read(), memory is not
    /// proportional to the entire directory's metadata.
    func stream(_ path: String, control: ScanControl, observeCall: ((Int32) -> Void)? = nil,
                consume: ([Entry]) -> Void) -> Bool {
        withoutActuallyEscaping(consume) { read(path, control: control, consume: $0, observeCall: observeCall) != nil }
    }

    /// Admission using names already needed for deterministic node ordering.
    /// Does not ask the filesystem for an expensive directory entry count or
    /// read a bounded prefix only to discard it when a wide directory overflows.
    /// This is an estimate, not a hard allocator/RSS limit.
    func fits(_ names: [String], control: ScanControl, allowSmallDirectory: Bool = false) -> Bool {
        guard maximumEstimatedBytes >= Self.bufferBytes,
              (allowSmallDirectory || names.count >= minimumEntries), names.count <= maximumEntries else { return false }
        var remaining = maximumEstimatedBytes - Self.bufferBytes
        for (index, name) in names.enumerated() {
            if index % 256 == 0, control.isCancelled { return false }
            let charge = Self.entryCharge(nameBytes: name.utf8.count)
            guard charge <= remaining else { return false }
            remaining -= charge
        }
        return !control.isCancelled
    }

    func read(_ path: String, control: ScanControl, includeDirectoryCounts: Bool = false,
              capacityHint: Int? = nil, polling: DirectoryReadPolling = .batch64,
              consume: (([Entry]) -> Void)? = nil, observeCall: ((Int32) -> Void)? = nil) -> [Entry]? {
        readRecords(path, control: control, includeDirectoryCounts: includeDirectoryCounts,
                    capacityHint: capacityHint, polling: polling, consume: consume,
                    observeCall: observeCall, namespaceCensusMayFinish: false)
    }

    /// Unverified candidate only. A sparse batch can stop before native EOF;
    /// caller must prove the full raw namespace with an independent census or
    /// discard it. The ordinary read/stream APIs always require native EOF.
    func readCensusCandidate(_ path: String, control: ScanControl,
                             polling: DirectoryReadPolling = .batch64,
                             observeCall: ((Int32) -> Void)? = nil) -> [Entry]? {
        readRecords(path, control: control, polling: polling, observeCall: observeCall,
                    namespaceCensusMayFinish: true)
    }

    private func readRecords(_ path: String, control: ScanControl, includeDirectoryCounts: Bool = false,
              capacityHint: Int? = nil, polling: DirectoryReadPolling = .batch64,
              consume: (([Entry]) -> Void)? = nil, observeCall: ((Int32) -> Void)? = nil,
              namespaceCensusMayFinish: Bool) -> [Entry]? {
        guard !control.isCancelled, maximumEstimatedBytes >= Self.bufferBytes else { return nil }
        let fd = open(path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return MacDirectoryScratch.withBuffer { storage -> [Entry]? in
        let bytes = UnsafeRawBufferPointer(start: storage, count: Self.bufferBytes)
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = Self.requiredCommon | UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_ERROR)
        attributes.dirattr = UInt32(ATTR_DIR_MOUNTSTATUS) | (includeDirectoryCounts ? UInt32(ATTR_DIR_ENTRYCOUNT) : 0); attributes.fileattr = Self.requiredFile
        var entries: [Entry] = []; var names: Set<String> = []; var estimatedBytes = Self.bufferBytes
        // Ordered callers already paid for an exact name count. Avoid geometric
        // array growth retaining a much larger backing buffer for wide folders.
        if consume == nil, let capacityHint, capacityHint > 0 {
            entries.reserveCapacity(min(capacityHint, maximumEntries))
        }
        while !control.isCancelled {
            let count = call(fd, &attributes, storage, Self.bufferBytes, UInt64(FSOPT_PACK_INVAL_ATTRS))
            observeCall?(count)
            guard count >= 0, count <= Self.bufferBytes / 4, !control.isCancelled else { return nil }
            if count == 0 { return entries }
            var start = 0
            for index in 0..<count {
                guard (Int(index) & polling.rawValue != 0 || !control.isCancelled), start <= Self.bufferBytes - 4 else { return nil }
                let length = Int(bytes.loadUnaligned(fromByteOffset: start, as: UInt32.self))
                guard length >= 36, length % 8 == 0, length <= Self.bufferBytes - start else { return nil }
                var cursor = Cursor(bytes: bytes, start: start, length: length)
                guard cursor.read(UInt32.self) != nil, let returned = cursor.read(attribute_set_t.self),
                      returned.commonattr & UInt32(ATTR_CMN_NAME) != 0,
                      let error = cursor.read(UInt32.self) else { return nil }
                let referenceOffset = cursor.offset
                guard let reference = cursor.read(attrreference_t.self), reference.attr_length > 0, reference.attr_length <= 8192 else { return nil }
                let nameOffset = referenceOffset + Int(reference.attr_dataoffset)
                let nameLength = Int(reference.attr_length)
                guard nameOffset >= cursor.offset, nameOffset <= length, nameLength <= length - nameOffset,
                      bytes[start + nameOffset + nameLength - 1] == 0 else { return nil }
                // Validate the borrowed bytes before constructing the owning
                // String. No Data copy or Character traversal is needed for
                // the two forbidden ASCII bytes; the borrow never escapes
                // this record or the next getattrlistbulk buffer refill.
                let rawName = UnsafeRawBufferPointer(rebasing: bytes[(start + nameOffset)..<(start + nameOffset + nameLength - 1)])
                guard !rawName.isEmpty, !rawName.contains(0), !rawName.contains(47),
                      let name = String(bytes: rawName, encoding: .utf8) else { return nil }
                if name == "." || name == ".." { start += length; continue }
                if consume == nil {
                    guard entries.count < maximumEntries, names.insert(name).inserted else { return nil }
                }
                let charge = Self.entryCharge(nameBytes: rawName.count)
                guard consume != nil || charge <= maximumEstimatedBytes - estimatedBytes else { return nil }
                estimatedBytes += charge
                let values: NativeFileMetadata?
                var directoryEntryCount: UInt32?
                if error != 0 {
                    // Name is enough for the unchanged scanner lstat/error path.
                    values = nil
                } else {
                    guard let device = cursor.read(dev_t.self), let type = cursor.read(fsobj_type_t.self),
                          let created = cursor.read(timespec.self), let modified = cursor.read(timespec.self),
                          let accessed = cursor.read(timespec.self), let permissions = cursor.read(UInt32.self),
                          let flags = cursor.read(UInt32.self), let inode = cursor.read(UInt64.self) else { return nil }
                    var mount: UInt32 = 0; var allocated: Int64 = 0; var logical: Int64 = 0
                    // The native API packs the object-specific group, not both
                    // dir+file groups, even with PACK_INVAL_ATTRS.
                    if type == VDIR.rawValue {
                        if includeDirectoryCounts {
                            guard let count = cursor.read(UInt32.self) else { return nil }
                            if returned.dirattr & UInt32(ATTR_DIR_ENTRYCOUNT) != 0 { directoryEntryCount = count }
                        }
                        guard let value = cursor.read(UInt32.self) else { return nil }; mount = value
                    }
                    if type == VREG.rawValue {
                        guard let a = cursor.read(Int64.self), let l = cursor.read(Int64.self) else { return nil }
                        allocated = a; logical = l
                    }
                    guard nameOffset >= cursor.offset else { return nil }
                    let complete = returned.commonattr & Self.requiredCommon == Self.requiredCommon &&
                        (type != VREG.rawValue || returned.fileattr & Self.requiredFile == Self.requiredFile) &&
                        (type != VDIR.rawValue || returned.dirattr & UInt32(ATTR_DIR_MOUNTSTATUS) != 0)
                    let knownType = type == VREG.rawValue || type == VDIR.rawValue || type == VLNK.rawValue ||
                        type == VBLK.rawValue || type == VCHR.rawValue || type == VSOCK.rawValue || type == VFIFO.rawValue
                    // A mount/firmlink record describes the underlying entry,
                    // while lstat(path) observes its mounted/redirected target.
                    let boundary = type == VDIR.rawValue && mount & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0 || flags & UInt32(SF_FIRMLINK) != 0
                    if boundary { directoryEntryCount = nil }
                    values = complete && knownType && !boundary && allocated >= 0 && logical >= 0
                        ? NativeFileMetadata(type: type, device: device, inode: inode, logical: logical, allocated: allocated,
                            created: created, accessed: accessed, modified: modified, permissions: permissions, flags: flags) : nil
                }
                entries.append(Entry(name: name, values: values, directoryEntryCount: directoryEntryCount)); start += length
            }
            if let consume {
                consume(entries)
                entries.removeAll(keepingCapacity: true)
                estimatedBytes = Self.bufferBytes
            } else if namespaceCensusMayFinish, start < Self.bufferBytes / 2 {
                // This is NOT an EOF assumption. Only the bounded worker uses
                // this candidate, and its independent namespace census must
                // prove completeness or discard it and run the original read.
                return entries
            }
        }
        return nil
        }
    }

    private struct Cursor {
        let bytes: UnsafeRawBufferPointer, start: Int, length: Int
        var offset = 0
        mutating func read<T: BitwiseCopyable>(_ type: T.Type) -> T? {
            guard MemoryLayout<T>.size <= length - offset else { return nil }
            let value = bytes.loadUnaligned(fromByteOffset: start + offset, as: T.self)
            offset += MemoryLayout<T>.size; return value
        }
    }
}
