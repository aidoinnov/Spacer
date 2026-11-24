import XCTest
import Darwin
@testable import SpaceSnifferCore

final class ScanOptimizationContractsTests: XCTestCase {
    private func fixture(_ count: Int = 100) throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/scan-contract-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<count { try Data([1]).write(to: root.appendingPathComponent("f\(i)")) }
        return root
    }
    func testWorkerCompletesUnsupportedBulkAndSkipsKnownMountBeforeStat() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let native = NativeDirectoryMetadata(call: { _,_,_,_,_ in errno = ENOTSUP; return -1 })
        let excluded = root.appendingPathComponent("f0").path
        let policy = ScanVolumePolicy(traversal: .selectedVolume, anchor: root.path, device: 1,
                                      mounts: [.init(path: excluded, isLocalAPFS: false)])
        let output = MacDirectoryBatchReader(native: native, volumePolicy: policy).readDirectory(at: root.path, control: ScanControl())
        guard case .listing(let listing) = output.value else { return XCTFail("expected bounded fallback") }
        let entries = try XCTUnwrap(listing.entries)
        XCTAssertEqual(entries.count, 100); XCTAssertEqual(output.statistics.statCalls, 99)
        XCTAssertNil(entries.first { $0.name == "f0" }?.values)
        XCTAssertEqual(entries.filter { $0.values != nil }.count, 99)
    }
    func testWorkerCensusRejectsOmittedAndRenamedBulkRows() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let expected = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        for omission in [true, false] {
            let native = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
                if omission { return 0 }
                let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
                if count > 0 {
                    let ref = buffer.loadUnaligned(fromByteOffset: 28, as: attrreference_t.self)
                    buffer.storeBytes(of: UInt8(120), toByteOffset: 28 + Int(ref.attr_dataoffset), as: UInt8.self)
                }
                return count
            })
            let output = OrderedDirectoryReader.prefetch(root.path, control: ScanControl(), native: native)
            guard case .listing(let listing) = output.value else { return XCTFail("expected authoritative fallback") }
            XCTAssertEqual(listing.names, expected); XCTAssertNil(listing.entries)
            XCTAssertGreaterThan(output.statistics.bulkNameMismatches, 0)
        }
    }
    func testSparseNativeCandidateRequiresIndependentCompleteNamespace() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let good = OrderedDirectoryReader.prefetch(root.path, control: ScanControl())
        guard case .listing(let complete) = good.value else { return XCTFail("expected validated metadata") }
        XCTAssertEqual(complete.entries?.count, 100)
        XCTAssertEqual(good.statistics.bulkCalls, 1, "census certifies the sparse batch without a duplicate native EOF call")
        XCTAssertEqual(good.statistics.openDirectoryCalls, 1, "independent namespace census remains mandatory")
        let truncated = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
            return min(count, 1) // deliberately hide rows in an otherwise valid record buffer
        })
        let bad = OrderedDirectoryReader.prefetch(root.path, control: ScanControl(), native: truncated)
        guard case .listing(let fallback) = bad.value else { return XCTFail("expected authoritative fallback") }
        XCTAssertEqual(fallback.names, complete.names); XCTAssertNil(fallback.entries)
        XCTAssertGreaterThan(bad.statistics.bulkNameMismatches, 0)
        XCTAssertGreaterThanOrEqual(bad.statistics.openDirectoryCalls, 2)
    }
    func testScratchIsReentrantPreservesOuterContentsAndReturnsOnThrow() {
        enum Failure: Error { case expected }
        MacDirectoryScratch.withBuffer { outer in
            outer.storeBytes(of: UInt64.max, as: UInt64.self)
            MacDirectoryScratch.withBuffer { inner in
                XCTAssertNotEqual(outer, inner); inner.storeBytes(of: UInt64(0), as: UInt64.self)
            }
            XCTAssertEqual(outer.load(as: UInt64.self), UInt64.max)
        }
        XCTAssertThrowsError(try MacDirectoryScratch.withBuffer { _ in throw Failure.expected })
        MacDirectoryScratch.withBuffer { first in
            MacDirectoryScratch.withBuffer { second in XCTAssertNotEqual(first, second) }
        }
    }
    func testCompactPathsAndMetadataPreservePublicMutationAndWireValues() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        for base in ["/", "/:", "/long-path/cafe\u{301}", "/한글"] {
            let path = SnapshotPath.joinPOSIX(base, "file😀")
            let literal = DiskNode(id: 1, parent: 0, path: path, name: "file😀")
            var compact = DiskNode(id: 1, parent: 0, storedPath: NodePathStorage(base: base, leaf: "file😀"), name: "file😀")
            XCTAssertEqual(compact, literal)
            XCTAssertEqual(try encoder.encode(compact), try encoder.encode(literal))
            for dates in [false, true] {
                compact.created = dates ? .distantPast : nil; compact.accessed = dates ? .distantFuture : nil
                compact.nativeAttributes = dates ? UInt32.max : nil; compact.nativeFlags = dates ? UInt8.max : nil
                compact.nativeType = dates ? 0 : nil; compact.ownAllocatedBytes = dates ? Int64.max : nil
                XCTAssertEqual(try JSONDecoder().decode(DiskNode.self, from: encoder.encode(compact)), compact)
            }
            compact.path = "C:\\folder\\file"; XCTAssertEqual(compact.path, "C:\\folder\\file")
        }
        var value = DiskNode(id: 0, parent: nil, path: "/", name: "/")
        let original = value
        value.created = .distantPast; value.created = nil
        value.nativeFlags = 0; value.nativeFlags = nil
        XCTAssertEqual(value, original)
        var snapshot = ScanSnapshot(rootPath: "/", nodes: [value]); let frozen = snapshot
        snapshot.nodes[0].path = "/changed"; snapshot.nodes[0].created = .distantFuture
        XCTAssertEqual(frozen.nodes[0], original)
    }
    func testPriorSynthesizedWireSchemaMatchesCompactStorage() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        for populated in [false, true] {
            var old = LegacyDiskNode(id: 1, parent: 0, path: "/cafe\u{301}/file", name: "file", logicalBytes: 123, allocatedBytes: 4096,
                                     modified: Date(timeIntervalSince1970: 1700000000), issue: populated ? "issue" : nil)
            if populated {
                old.created = .distantPast; old.accessed = .distantFuture; old.nativeAttributes = .max
                old.nativeFlags = .max; old.nativeType = 0; old.ownAllocatedBytes = 0; old.fileIdentity = "01:002"
            }
            let bytes = try encoder.encode(old)
            let current = try JSONDecoder().decode(DiskNode.self, from: bytes)
            XCTAssertEqual(try encoder.encode(current), bytes)
        }
    }
    func testNegativeAdmissionExpiresBeforeLaterLargeSiblings() throws {
        let root = try fixture(0); defer { try? FileManager.default.removeItem(at: root) }
        // DFS visits b199...b000: four sampled siblings and the first 100 are tiny.
        for index in 0..<200 {
            let child = root.appendingPathComponent(String(format: "b%03d", index))
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            for file in 0..<(index < 100 ? 96 : 1) { try Data([1]).write(to: child.appendingPathComponent("f\(file)")) }
        }
        var statistics = ScanIOStatistics()
        let result = DiskScanner.scan(root, metadataBackend: .ordered(.orderedScan), directoryConcurrency: 2, diagnostics: { statistics = $0 })
        XCTAssertEqual(result.fileCount, 9700); XCTAssertEqual(result.issueCount, 0)
        XCTAssertGreaterThan(statistics.prefetchUsed, 0, "a rejected initial sample must not veto later large siblings")
        _ = try result.validated()
    }
}

private struct LegacyDiskNode: Codable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var parent: Int?
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var isSymbolicLink: Bool
    public var logicalBytes: Int64
    public var allocatedBytes: Int64
    public var created: Date?
    public var accessed: Date?
    public var nativeAttributes: UInt32?
    public var nativeFlags: UInt8?
    public var nativeType: UInt8?
    public var modified: Date
    public var children: [Int]
    public var issue: String?
    @FileIdentity public var fileIdentity: String? = nil
    var fileIdentityKey: FileIdentity? { _fileIdentity.isPresent ? _fileIdentity : nil }
    public var ownAllocatedBytes: Int64?
    public func bytes(_ mode: SizeMode) -> Int64 { mode == .logical ? logicalBytes : allocatedBytes }
    mutating func setNativeFileIdentity(device: Int64, inode: UInt64) {
        _fileIdentity = FileIdentity(device: device, inode: inode)
    }
    public init(id: Int, parent: Int?, path: String, name: String, isDirectory: Bool = false,
                isSymbolicLink: Bool = false, logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0,
                modified: Date = .distantPast, children: [Int] = [], issue: String? = nil) {
        self.id = id; self.parent = parent; self.path = path; self.name = name
        self.isDirectory = isDirectory; self.isSymbolicLink = isSymbolicLink
        self.logicalBytes = logicalBytes; self.allocatedBytes = allocatedBytes
        self.modified = modified; self.children = children; self.issue = issue
    }
}

