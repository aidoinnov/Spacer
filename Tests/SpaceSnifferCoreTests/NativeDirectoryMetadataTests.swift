import XCTest
import Darwin
@testable import SpaceSnifferCore

final class NativeDirectoryMetadataTests: XCTestCase, @unchecked Sendable {
    private func fixture(wide: Int = 0) throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("sniffer-bulk-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for branch in 0..<4 {
            let folder = root.appendingPathComponent("branch-\(branch)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<16 { try Data(repeating: UInt8(index), count: [0,1,513,1025,4097][index%5]).write(to: folder.appendingPathComponent("file-\(index).bin")) }
        }
        for index in 0..<wide { try Data([1]).write(to: root.appendingPathComponent("wide-\(index).bin")) }
        for name in [".hidden", "한글-😀-cafe\u{301}", String(repeating: "long", count: 50)] { try Data([1,2]).write(to: root.appendingPathComponent(name)) }
        try FileManager.default.linkItem(at: root.appendingPathComponent("branch-0/file-1.bin"), to: root.appendingPathComponent("alias"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("cycle").path, withDestinationPath: ".")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("broken").path, withDestinationPath: "absent")
        XCTAssertEqual(chmod(root.appendingPathComponent(".hidden").path, 0o444), 0)
        XCTAssertEqual(chflags(root.appendingPathComponent(".hidden").path, UInt32(UF_HIDDEN)), 0)
        return root
    }
    private func resetTimes(_ root: URL) throws {
        let iterator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let paths = [root] + iterator.compactMap { $0 as? URL }
        for path in paths {
            var dates = [timespec(tv_sec: 1_700_000_000, tv_nsec: 0),timespec(tv_sec: 1_700_000_000, tv_nsec: 0)]
            let result = dates.withUnsafeMutableBufferPointer { utimensat(AT_FDCWD, path.path, $0.baseAddress!, AT_SYMLINK_NOFOLLOW) }
            XCTAssertEqual(result, 0, path.path)
        }
    }
    private func compare(_ root: URL, reader: NativeDirectoryMetadata = .init(), file: StaticString = #filePath, line: UInt = #line) throws {
        try resetTimes(root)
        let original = DiskScanner.scan(root, metadataBackend: .posix)
        try resetTimes(root)
        let candidate = DiskScanner.scan(root, metadataBackend: .bulk(reader))
        XCTAssertEqual(Array(candidate.nodes), Array(original.nodes), file: file, line: line)
        XCTAssertEqual(candidate.fileCount, original.fileCount, file: file, line: line)
        XCTAssertEqual(candidate.folderCount, original.folderCount, file: file, line: line)
        XCTAssertEqual(candidate.issueCount, original.issueCount, file: file, line: line)
        XCTAssertEqual(candidate.issues, original.issues, file: file, line: line)
        XCTAssertFalse(candidate.cancelled, file: file, line: line)
    }
    @discardableResult private func compareOrdered(_ root: URL, reader: NativeDirectoryMetadata = .orderedScan,
                                                   backend: DiskScanner.MetadataBackend? = nil,
                                                   file: StaticString = #filePath, line: UInt = #line) throws -> ScanIOStatistics {
        try resetTimes(root)
        let original = DiskScanner.scan(root, metadataBackend: .posix)
        try resetTimes(root)
        var stats = ScanIOStatistics()
        let candidate = DiskScanner.scan(root, metadataBackend: backend ?? .ordered(reader), diagnostics: { stats = $0 })
        // Node IDs/children and every field are equal, not just normalized paths.
        XCTAssertEqual(Array(candidate.nodes), Array(original.nodes), file: file, line: line)
        XCTAssertEqual(candidate.fileCount, original.fileCount, file: file, line: line)
        XCTAssertEqual(candidate.folderCount, original.folderCount, file: file, line: line)
        XCTAssertEqual(candidate.issues, original.issues, file: file, line: line)
        XCTAssertEqual(candidate.issueCount, original.issueCount, file: file, line: line)
        XCTAssertFalse(candidate.cancelled, file: file, line: line)
        _ = try candidate.validated()
        let originalWeights = original.nodes.map(\.allocatedBytes)
        let candidateWeights = candidate.nodes.map(\.allocatedBytes)
        XCTAssertEqual(Report.simpleFileList(candidate, ids: Set(candidate.nodes.indices), weights: candidateWeights),
                       Report.simpleFileList(original, ids: Set(original.nodes.indices), weights: originalWeights), file: file, line: line)
        var stableOriginal = original, stableCandidate = candidate
        stableOriginal.volumeFree = 0; stableCandidate.volumeFree = 0
        XCTAssertEqual(try SNSSnapshot.encode(stableCandidate), try SNSSnapshot.encode(stableOriginal), file: file, line: line)
        return stats
    }

    func testAutomaticMetadataPolicyIsLocalAPFSOnlyAndConservativeOnFailure() throws {
        XCTAssertTrue(ScanMetadataPolicy.allowsBulk(filesystem: "apfs", isLocal: true))
        for filesystem in ["apfs", "smbfs", "nfs", "hfs", "exfat", ""] {
            XCTAssertFalse(ScanMetadataPolicy.allowsBulk(filesystem: filesystem, isLocal: false))
            if filesystem != "apfs" { XCTAssertFalse(ScanMetadataPolicy.allowsBulk(filesystem: filesystem, isLocal: true)) }
        }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var info = stat(); XCTAssertEqual(lstat(root.path, &info), 0)
        var policy = ScanMetadataPolicy()
        let nativeDecision = policy.allowsBulk(path: root.path, device: info.st_dev)
        // The same device reuses its run-local decision, even on a missing path.
        XCTAssertEqual(policy.allowsBulk(path: root.path + "/absent", device: info.st_dev), nativeDecision)
        var unknown = ScanMetadataPolicy()
        XCTAssertFalse(unknown.allowsBulk(path: root.path + "/absent", device: info.st_dev))
        XCTAssertFalse(unknown.allowsBulk(path: root.path, device: info.st_dev))
        let stats = try compareOrdered(root, backend: DiskScanner.defaultMetadataBackend)
        XCTAssertEqual(stats.bulkCalls > 0, nativeDecision)
    }

    func testOrderedAdmissionSkipsTinyDirectoriesAndHonorsSixteenEntryBoundary() {
        let reader = NativeDirectoryMetadata.orderedScan
        let control = ScanControl()
        XCTAssertFalse(reader.fits((0..<15).map { "f\($0)" }, control: control))
        XCTAssertTrue(reader.fits((0..<16).map { "f\($0)" }, control: control))
        // The same byte budget can admit short names beyond the old count
        // ceiling, while long names at that count still exceed the budget.
        XCTAssertTrue(reader.fits(Array(repeating: "f", count: 131_073), control: control))
        XCTAssertFalse(reader.fits(Array(repeating: String(repeating: "x", count: 255), count: 131_073), control: control))
        XCTAssertFalse(reader.fits(Array(repeating: "f", count: 262_145), control: control))
        control.cancel()
        XCTAssertFalse(reader.fits((0..<16).map { "f\($0)" }, control: control))
    }

    func testOrderedNativeWideLegacyBoundariesPreserveExactExports() throws {
        for count in [4095, 4096, 4097] {
            let root = try fixture(wide: count)
            defer { try? FileManager.default.removeItem(at: root) }
            let stats = try compareOrdered(root)
            XCTAssertEqual(stats.bulkPreflightSkips, 0)
            XCTAssertEqual(stats.bulkNameMismatches, 0)
        }
    }

    func testOrderedRenameBetweenListingsFallsBackAndNextScanConverges() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let victim = root.appendingPathComponent("victim").path
        let replacement = root.appendingPathComponent("replacement").path
        try Data([1]).write(to: URL(fileURLWithPath: victim))
        let calls = MetadataCalls()
        let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, size, options in
            if calls.next() == 1 { XCTAssertEqual(rename(victim, replacement), 0) }
            return getattrlistbulk(fd, &attrs, buffer, size, options)
        })
        var stats = ScanIOStatistics()
        let raced = DiskScanner.scan(root, metadataBackend: .ordered(reader), diagnostics: { stats = $0 })
        XCTAssertEqual(stats.bulkNameMismatches, 1)
        XCTAssertEqual(raced.issueCount, 1)
        XCTAssertTrue(raced.issues.contains { $0.contains("victim") })
        XCTAssertFalse(raced.nodes.contains { $0.path == replacement || $0.path == victim })
        _ = try raced.validated()
        // The next stable scan converges; the first scan never claims atomicity.
        try compareOrdered(root, backend: DiskScanner.defaultMetadataBackend)
    }

    func testRecursiveMetadataParityIncludesUnicodeFlagsLinksAndForks() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fork = root.appendingPathComponent("resource.bin"); try Data([1,2,3]).write(to: fork)
        let content = Data(repeating: 3, count: 4097)
        let status = content.withUnsafeBytes { setxattr(fork.path, "com.apple.ResourceFork", $0.baseAddress!, $0.count, 0, 0) }
        XCTAssertEqual(status, 0)
        let entries = try XCTUnwrap(NativeDirectoryMetadata().read(root.path, control: ScanControl()))
        XCTAssertTrue(entries.allSatisfy { $0.values != nil })
        try compare(root)
        try compareAdaptive(root)
        try compareStreaming(root)
        try compareOrdered(root)
    }
    func testSparsePhysicalBytesMatchStatAfterPunchingHole() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("sparse.bin").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600); XCTAssertGreaterThanOrEqual(fd, 0); guard fd >= 0 else { return }
        defer { close(fd) }
        XCTAssertEqual(ftruncate(fd, 8*1024*1024), 0)
        var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: 0, fp_length: 8*1024*1024)
        let result = fcntl(fd, F_PUNCHHOLE, &hole)
        if result != 0 { throw XCTSkip("fixture filesystem does not support F_PUNCHHOLE errno=\(errno)") }
        var info = stat(); XCTAssertEqual(lstat(path, &info), 0)
        XCTAssertLessThan(Int64(info.st_blocks)*512, info.st_size)
        try compare(root)
        try compareAdaptive(root)
        try compareStreaming(root)
        try compareOrdered(root)
    }
    func testWideAndMemoryCapsFallBackWithoutDroppingOrDuplicatingNodes() throws {
        let root = try fixture(wide: 4100); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(NativeDirectoryMetadata().read(root.path, control: ScanControl()))
        XCTAssertNil(NativeDirectoryMetadata(maximumEstimatedBytes: 1024).read(root.path, control: ScanControl()))
        try compare(root)
        try compare(root, reader: NativeDirectoryMetadata(maximumEntries: 2))
    }
    func testUnsupportedMalformedAndLaterBatchFailureAreWholeDirectoryFallbacks() throws {
        let root = try fixture(wide: 700); defer { try? FileManager.default.removeItem(at: root) }
        let unsupported = NativeDirectoryMetadata(call: { _,_,_,_,_ in errno = ENOTSUP; return -1 })
        XCTAssertNil(unsupported.read(root.path, control: ScanControl())); try compare(root, reader: unsupported)
        let malformed = NativeDirectoryMetadata(call: { _,_,buffer,_,_ in buffer.storeBytes(of: UInt32.max, as: UInt32.self); return 1 })
        XCTAssertNil(malformed.read(root.path, control: ScanControl())); try compare(root, reader: malformed)
        let calls = MetadataCalls()
        let late = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            if calls.next() == 2 { errno = EIO; return -1 }
            return getattrlistbulk(fd, &attrs, buffer, bytes, flags)
        })
        try compare(root, reader: late)
        XCTAssertGreaterThanOrEqual(calls.count, 2)
        let invalidName = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
            if count > 0 { buffer.storeBytes(of: UInt32(0), toByteOffset: 32, as: UInt32.self) }
            return count
        })
        try compare(root, reader: invalidName)
    }
    func testNamedPartialMetadataAndEntryErrorUseOriginalStatPath() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for fault in 0..<4 {
            let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
                let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
                if count > 0 {
                    if fault == 1 { buffer.storeBytes(of: UInt32(EACCES), toByteOffset: 24, as: UInt32.self) }
                    else if fault == 2 { buffer.storeBytes(of: UInt32.max, toByteOffset: 40, as: UInt32.self) }
                    else if fault == 3 { buffer.storeBytes(of: UInt32(SF_FIRMLINK), toByteOffset: 96, as: UInt32.self) }
                    else {
                        let raw = buffer.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
                        buffer.storeBytes(of: raw & ~UInt32(ATTR_CMN_FILEID), toByteOffset: 4, as: UInt32.self)
                    }
                }
                return count
            })
            let entries = try XCTUnwrap(reader.read(root.path, control: ScanControl()))
            XCTAssertTrue(entries.contains { $0.values == nil }); try compare(root, reader: reader)
            try compareOrdered(root, reader: reader)
        }
    }
    func testMountMetadataIsNotUsedAsMountedRootIdentity() throws {
        let entries = try XCTUnwrap(NativeDirectoryMetadata().read("/Volumes", control: ScanControl()))
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            if let values = entry.values {
                var info = stat(); XCTAssertEqual(lstat("/Volumes/" + entry.name, &info), 0)
                XCTAssertEqual(values.device, info.st_dev); XCTAssertEqual(values.inode, info.st_ino)
            }
        }
        // This host currently has multiple mounted volumes. Boundary values are
        // deliberately left nil; scanner append performs its original lstat.
        XCTAssertTrue(entries.contains { $0.values == nil })
        let adaptive = try XCTUnwrap(NativeDirectoryMetadata().read("/Volumes", control: ScanControl(), includeDirectoryCounts: true))
        XCTAssertTrue(adaptive.filter { $0.values == nil }.allSatisfy { $0.directoryEntryCount == nil })
    }
    func testCancelDuringCollectionPublishesNoPartialMetadataAndClosesPrivateFD() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let control = ScanControl(); let observed = MetadataFD()
        let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            observed.set(fd); let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags); control.cancel(); return count
        })
        XCTAssertNil(reader.read(root.path, control: control))
        let oldFD = try XCTUnwrap(observed.value); errno = 0
        XCTAssertEqual(fcntl(oldFD, F_GETFD), -1); XCTAssertEqual(errno, EBADF)
        let cancelled = DiskScanner.scan(root, control: control, metadataBackend: .bulk(reader))
        XCTAssertTrue(cancelled.cancelled); XCTAssertEqual(cancelled.nodes.count, 1)
        XCTAssertEqual(cancelled.fileCount, 0)
    }
    private func compareAdaptive(_ root: URL, reader: NativeDirectoryMetadata = .init(), file: StaticString = #filePath, line: UInt = #line) throws {
        try resetTimes(root); let original = DiskScanner.scan(root, metadataBackend: .posix)
        try resetTimes(root); let candidate = DiskScanner.scan(root, metadataBackend: .adaptive(reader))
        XCTAssertEqual(Array(candidate.nodes), Array(original.nodes), file: file, line: line)
        XCTAssertEqual(candidate.fileCount, original.fileCount, file: file, line: line)
        XCTAssertEqual(candidate.folderCount, original.folderCount, file: file, line: line)
        XCTAssertEqual(candidate.issues, original.issues, file: file, line: line)
        XCTAssertEqual(candidate.issueCount, original.issueCount, file: file, line: line)
        XCTAssertFalse(candidate.cancelled, file: file, line: line)
    }
    func testAdaptiveRealCountPropagatesWithoutChangingFields() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let reader = NativeDirectoryMetadata()
        let entries = try XCTUnwrap(reader.read(root.path, control: ScanControl(), includeDirectoryCounts: true))
        XCTAssertEqual(reader.entryCount(root.path, control: ScanControl()), UInt32(entries.count))
        XCTAssertEqual(entries.filter { $0.values?.isDirectory == true }.count, 4)
        XCTAssertTrue(entries.filter { $0.values?.isDirectory == true }.allSatisfy { $0.directoryEntryCount == 16 })
        let calls = MetadataCalls()
        let oneRootQuery = NativeDirectoryMetadata(countCall: { path, attrs, buffer, size, options in
            _ = calls.next(); return getattrlist(path, &attrs, buffer, size, options)
        })
        try compareAdaptive(root, reader: oneRootQuery)
        XCTAssertEqual(calls.count, 1)
    }
    func testAdaptiveUnavailableAndWideHintNeverAttemptBulk() throws {
        let root = try fixture(wide: 4100); defer { try? FileManager.default.removeItem(at: root) }
        let calls = MetadataCalls()
        let unused: NativeDirectoryMetadata.BulkCall = { _,_,_,_,_ in _ = calls.next(); errno = EIO; return -1 }
        let unavailable = NativeDirectoryMetadata(countCall: { _,_,_,_,_ in errno = ENOTSUP; return -1 }, call: unused)
        try compareAdaptive(root, reader: unavailable)
        let wide = NativeDirectoryMetadata(call: unused); try compareAdaptive(root, reader: wide)
        XCTAssertEqual(calls.count, 0)
        for malformed in [false,true] {
            let reader = NativeDirectoryMetadata(countCall: { _,_,buffer,_,_ in
                buffer.initializeMemory(as: UInt8.self, repeating: 0, count: 32)
                buffer.storeBytes(of: UInt32(malformed ? 4 : 28), as: UInt32.self); return 0
            }, call: unused)
            try compareAdaptive(root, reader: reader)
        }
        XCTAssertEqual(calls.count, 0)
    }
    func testAdaptiveStaleAndMissingChildCountsRemainConservative() throws {
        let root = try fixture(wide: 4100); defer { try? FileManager.default.removeItem(at: root) }
        let stale = NativeDirectoryMetadata(countCall: { path, attrs, buffer, size, options in
            let result = getattrlist(path, &attrs, buffer, size, options)
            if result == 0 { buffer.storeBytes(of: UInt32(0), toByteOffset: 24, as: UInt32.self) }
            return result
        })
        // Stale underestimate still reaches the existing all-or-nothing cap.
        try compareAdaptive(root, reader: stale)
        let narrow = try fixture(); defer { try? FileManager.default.removeItem(at: narrow) }
        let missing = NativeDirectoryMetadata(call: { fd, attrs, buffer, size, options in
            let count = getattrlistbulk(fd, &attrs, buffer, size, options)
            var offset = 0
            if count > 0 { for _ in 0..<count {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                let bits = buffer.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self)
                buffer.storeBytes(of: bits & ~UInt32(ATTR_DIR_ENTRYCOUNT), toByteOffset: offset + 12, as: UInt32.self)
                offset += length
            } }
            return count
        })
        let entries = try XCTUnwrap(missing.read(narrow.path, control: ScanControl(), includeDirectoryCounts: true))
        XCTAssertTrue(entries.allSatisfy { $0.directoryEntryCount == nil })
        try compareAdaptive(narrow, reader: missing)
        let control = ScanControl()
        let cancelled = NativeDirectoryMetadata(countCall: { _,_,_,_,_ in control.cancel(); return -1 })
        XCTAssertNil(cancelled.entryCount(narrow.path, control: control))
        let snapshot = DiskScanner.scan(narrow, control: control, metadataBackend: .adaptive(cancelled))
        XCTAssertTrue(snapshot.cancelled); XCTAssertEqual(snapshot.fileCount, 0)
    }
    private func compareStreaming(_ root: URL, reader: NativeDirectoryMetadata = .init()) throws {
        try resetTimes(root)
        let original = DiskScanner.scan(root, metadataBackend: .posix)
        try resetTimes(root)
        let candidate = DiskScanner.scan(root, metadataBackend: .streaming(reader))
        // Streaming enumeration changes node IDs/order. Compare all filesystem
        // fields and parent/child relationships by path, independently of IDs.
        func normalized(_ snapshot: ScanSnapshot) -> [String: DiskNode] {
            var output: [String: DiskNode] = [:]
            var childrenByParent: [Int: [String]] = [:]
            for node in snapshot.nodes {
                if let parent = node.parent { childrenByParent[parent, default: []].append(node.path) }
            }
            for var node in snapshot.nodes {
                let childPaths = node.children.map { snapshot.nodes[$0].path }.sorted()
                XCTAssertEqual(Set(childPaths).count, childPaths.count)
                if let parent = node.parent {
                    XCTAssertEqual(URL(fileURLWithPath: node.path).deletingLastPathComponent().path,
                                   snapshot.nodes[parent].path)
                }
                let expectedChildren = (childrenByParent[node.id] ?? []).sorted()
                XCTAssertEqual(childPaths, expectedChildren)
                node.id = 0; node.parent = nil; node.children = []
                XCTAssertNil(output.updateValue(node, forKey: node.path))
            }
            return output
        }
        XCTAssertEqual(normalized(candidate), normalized(original))
        XCTAssertEqual(candidate.fileCount, original.fileCount)
        XCTAssertEqual(candidate.folderCount, original.folderCount)
        XCTAssertEqual(candidate.issueCount, original.issueCount)
        XCTAssertFalse(candidate.cancelled)
        _ = try candidate.validated()
    }

    func testStreamingWideDirectoryIgnoresOldWholeDirectoryCapsAndMatchesEveryField() throws {
        let root = try fixture(wide: 4100); defer { try? FileManager.default.removeItem(at: root) }
        try compareStreaming(root, reader: .init(maximumEntries: 2))
    }

    func testStreamingLaterBatchFailureAndDuplicateDeliveryCannotDoubleCount() throws {
        let root = try fixture(wide: 700); defer { try? FileManager.default.removeItem(at: root) }
        let calls = MetadataCalls()
        let lateFailure = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            if calls.next() == 2 { errno = EIO; return -1 }
            return getattrlistbulk(fd, &attrs, buffer, bytes, flags)
        })
        try compareStreaming(root, reader: lateFailure)
        XCTAssertGreaterThan(calls.count, 2)
        let unsupported = NativeDirectoryMetadata(call: { _,_,_,_,_ in errno = ENOTSUP; return -1 })
        try compareStreaming(root, reader: unsupported)
        let malformed = NativeDirectoryMetadata(call: { _,_,buffer,_,_ in
            buffer.storeBytes(of: UInt32.max, as: UInt32.self); return 1
        })
        try compareStreaming(root, reader: malformed)
    }

    func testStreamingReusesMetadataAndLateFallbackOnlyStatsUnreadNames() throws {
        let root = try fixture(wide: 700); defer { try? FileManager.default.removeItem(at: root) }
        var fastIO = ScanIOStatistics()
        let fast = DiskScanner.scan(root, metadataBackend: .streaming(.init()), diagnostics: { fastIO = $0 })
        XCTAssertEqual(fastIO.statCalls, 1)
        XCTAssertEqual(fastIO.fallbackDirectories, 0)
        XCTAssertEqual(fastIO.readDirectoryCalls, 0)
        XCTAssertGreaterThan(fastIO.bulkCalls, 1)
        let calls = MetadataCalls()
        let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            if calls.next() == 2 { errno = EIO; return -1 }
            return getattrlistbulk(fd, &attrs, buffer, bytes, flags)
        })
        var fallbackIO = ScanIOStatistics()
        let fallback = DiskScanner.scan(root, metadataBackend: .streaming(reader), diagnostics: { fallbackIO = $0 })
        XCTAssertEqual(fallback.fileCount, fast.fileCount)
        XCTAssertEqual(fallback.nodes[0].allocatedBytes, fast.nodes[0].allocatedBytes)
        XCTAssertEqual(fallbackIO.fallbackDirectories, 1)
        XCTAssertGreaterThan(fallbackIO.statCalls, 1)
        XCTAssertLessThan(fallbackIO.statCalls, fallback.nodes.count)
        XCTAssertGreaterThan(fallbackIO.reusedMetadataEntries, 0)
        _ = try fallback.validated()
    }

    func testStreamingCancellationClosesPrivateFDAndKeepsPartialTreeValid() throws {
        let root = try fixture(wide: 700); defer { try? FileManager.default.removeItem(at: root) }
        let control = ScanControl(), descriptor = MetadataFD()
        let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            descriptor.set(fd)
            let result = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
            control.cancel()
            return result
        })
        let result = DiskScanner.scan(root, control: control, metadataBackend: .streaming(reader))
        XCTAssertTrue(result.cancelled)
        _ = try result.validated()
        let fd = try XCTUnwrap(descriptor.value)
        XCTAssertEqual(fcntl(fd, F_GETFD), -1)
        XCTAssertEqual(errno, EBADF)
    }

    func testOrderedWidePreservesNodeIDsExportBytesAndReusesMetadata() throws {
        let root = try fixture(wide: 4100); defer { try? FileManager.default.removeItem(at: root) }
        let stats = try compareOrdered(root)
        XCTAssertEqual(stats.statCalls, 1)
        XCTAssertEqual(stats.bulkPreflightSkips, 0)
        XCTAssertEqual(stats.bulkNameMismatches, 0)
        XCTAssertGreaterThan(stats.reusedMetadataEntries, 4100)
    }

    func testOrderedPreflightSkipsBulkBeforeReadingWhenCountOrMemoryExceedsBudget() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let forbidden: NativeDirectoryMetadata.BulkCall = { _,_,_,_,_ in XCTFail("preflight must not issue bulk call"); return -1 }
        // The fixture's every directory exceeds 2 entries, including leaf folders.
        let countStats = try compareOrdered(root, reader: .init(maximumEntries: 2, call: forbidden))
        XCTAssertEqual(countStats.bulkCalls, 0)
        XCTAssertGreaterThan(countStats.bulkPreflightSkips, 0)
        let byteStats = try compareOrdered(root, reader: .init(maximumEstimatedBytes: 1024, call: forbidden))
        XCTAssertEqual(byteStats.bulkCalls, 0)
    }

    func testOrderedUnsupportedMalformedAndLaterFailureReuseFirstNamesWithoutReopening() throws {
        let root = try fixture(wide: 700); defer { try? FileManager.default.removeItem(at: root) }
        for kind in 0..<3 {
            let calls = MetadataCalls()
            let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
                let next = calls.next()
                if kind == 0 || (kind == 2 && next == 2) { errno = kind == 0 ? ENOTSUP : EIO; return -1 }
                if kind == 1 { buffer.storeBytes(of: UInt32.max, as: UInt32.self); return 1 }
                return getattrlistbulk(fd, &attrs, buffer, bytes, flags)
            })
            let stats = try compareOrdered(root, reader: reader)
            XCTAssertEqual(stats.openDirectoryCalls, 5) // root and four branches, once each
            XCTAssertGreaterThan(stats.fallbackDirectories, 0)
        }
    }

    func testMalformedNameBytesFallBackWithoutInventingPaths() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        // Invalid UTF-8, embedded NUL and a path separator must all reject
        // the entire batch; the existing POSIX names remain authoritative.
        for byte: UInt8 in [0xff, 0, 47] {
            let descriptor = MetadataFD()
            let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
                descriptor.set(fd)
                let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
                if count > 0 {
                    let reference = buffer.loadUnaligned(fromByteOffset: 28, as: attrreference_t.self)
                    let location = 28 + Int(reference.attr_dataoffset)
                    buffer.storeBytes(of: byte, toByteOffset: location, as: UInt8.self)
                }
                return count
            })
            let stats = try compareOrdered(root, reader: reader)
            XCTAssertGreaterThan(stats.fallbackDirectories, 0)
            let fd = try XCTUnwrap(descriptor.value)
            XCTAssertEqual(fcntl(fd, F_GETFD), -1)
            XCTAssertEqual(errno, EBADF)
        }
    }

    func testOrderedNameRaceRejectsWholeBatchAndDoesNotInventTheRenamedPath() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
            if count > 0 {
                let reference = buffer.loadUnaligned(fromByteOffset: 28, as: attrreference_t.self)
                let location = 28 + Int(reference.attr_dataoffset)
                buffer.storeBytes(of: UInt8(120), toByteOffset: location, as: UInt8.self)
            }
            return count
        })
        let stats = try compareOrdered(root, reader: reader)
        XCTAssertGreaterThan(stats.bulkNameMismatches, 0)
        XCTAssertEqual(stats.openDirectoryCalls, 5)
    }

    func testOrderedCancellationDuringBulkClosesCursorAndKeepsValidPartial() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let control = ScanControl(), descriptor = MetadataFD()
        let reader = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            descriptor.set(fd)
            let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
            control.cancel(); return count
        })
        let snapshot = DiskScanner.scan(root, control: control, metadataBackend: .ordered(reader))
        XCTAssertTrue(snapshot.cancelled)
        _ = try snapshot.validated()
        let fd = try XCTUnwrap(descriptor.value)
        XCTAssertEqual(fcntl(fd, F_GETFD), -1); XCTAssertEqual(errno, EBADF)
    }

    func testDeniedAndRemovedDirectoryKeepsLegacyIssueSemantics() throws {
        if getuid() == 0 { throw XCTSkip("root bypasses permission fixture") }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let denied = root.appendingPathComponent("branch-0").path
        XCTAssertEqual(chmod(denied, 0), 0); defer { _ = chmod(denied, 0o700) }
        let original = DiskScanner.scan(root, metadataBackend: .posix)
        let candidate = DiskScanner.scan(root, metadataBackend: .bulk(.init()))
        XCTAssertEqual(candidate.issueCount, original.issueCount); XCTAssertEqual(candidate.fileCount, original.fileCount)
        XCTAssertEqual(candidate.nodes[0].logicalBytes, original.nodes[0].logicalBytes)
        XCTAssertEqual(candidate.nodes[0].allocatedBytes, original.nodes[0].allocatedBytes)
        try compareStreaming(root)
        try compareOrdered(root)
        _ = chmod(denied, 0o700)
        let removed = DiskScanner.scan(root, metadataBackend: .bulk(.init()), heartbeat: { _ in try? FileManager.default.removeItem(at: root) })
        XCTAssertEqual(removed.issueCount, 1); XCTAssertEqual(removed.nodes.count, 1); XCTAssertFalse(removed.cancelled)
    }
}

private final class MetadataCalls: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
    var count: Int { lock.withLock { value } }
}
private final class MetadataFD: @unchecked Sendable {
    private let lock = NSLock(); private var stored: Int32?
    func set(_ fd: Int32) { lock.withLock { stored = fd } }
    var value: Int32? { lock.withLock { stored } }
}
