import XCTest
import Darwin
@testable import SpaceSnifferAutomation
import SpaceSnifferCore

final class AutomationTests: XCTestCase, @unchecked Sendable {
    private func context() -> QueryContext {
        var s = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 9, allocatedBytes: 12288, children: [1, 3]),
            DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", isDirectory: true, logicalBytes: 4, allocatedBytes: 8192, children: [2]),
            DiskNode(id: 2, parent: 1, path: "/r/a/one.bin", name: "one.bin", logicalBytes: 4, allocatedBytes: 8192),
            DiskNode(id: 3, parent: 0, path: "/r/two.txt", name: "two.txt", logicalBytes: 5, allocatedBytes: 4096)])
        s.fileCount = 2; s.folderCount = 2; s.tags["/r/a"] = 4
        return QueryContext(snapshot: s, weights: [9,4,4,5], filter: try! ScanFilter(""), mode: .logical, showHidden: true, revision: "rev1", focus: 0, selection: nil)
    }
    func testJSONPreservesIntegerPrecisionAndTypes() throws {
        let value: JSONValue = .object(["bytes": .integer(9_007_199_254_740_993), "boolean": .bool(true), "null": .null, "text": .string("한글\n")])
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
    func testPaginationAndRevisionGuard() throws {
        let c = context()
        let first = try c.query(command: "tree_children", arguments: ["limit": .int(1)])
        XCTAssertEqual(first.object?["next_offset"], .int(1))
        let second = try c.query(command: "tree_children", arguments: ["limit": .int(1), "offset": .int(1), "revision": .string("rev1")])
        XCTAssertEqual(second.object?["next_offset"], .null)
        XCTAssertThrowsError(try c.query(command: "tree_children", arguments: ["revision": .string("old")]))
        XCTAssertThrowsError(try c.query(command: "tree_children", arguments: ["limit": .int(501)]))
    }
    func testQueryBudgetDoesNotPretendEmptyPageIsComplete() throws {
        let c = context()
        let first = try c.query(command: "query_nodes", arguments: ["budget": .int(1), "expression": .string("*.bin")])
        XCTAssertEqual(first.object?["complete"], .bool(false)); XCTAssertEqual(first.object?["next_offset"], .int(1))
        let next = try c.query(command: "query_nodes", arguments: ["offset": .int(1), "budget": .int(3), "expression": .string("*.bin")])
        guard case .array(let rows) = next.object?["items"] else { return XCTFail() }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].object?["path"], .string("/r/a/one.bin"))
    }
    func testLargestHeapAndExactMetadata() throws {
        let c = context()
        let top = try c.query(command: "largest_nodes", arguments: ["limit": .int(1), "kind": .string("files")])
        guard case .array(let rows) = top.object?["items"] else { return XCTFail() }
        XCTAssertEqual(rows[0].object?["path"], .string("/r/two.txt"))
        let info = try c.query(command: "node_info", arguments: ["path": .string("/r/a/one.bin")])
        XCTAssertEqual(info.object?["node"]?.object?["inherited_tag_mask"], .int(4))
        XCTAssertThrowsError(try c.nodeID(path: "/r/aa/one.bin"))
    }
    func testProcessMetricsComeFromThisProcess() {
        let p = ProcessMetrics.read()
        XCTAssertEqual(p.object?["pid"], .int(Int(getpid())))
        XCTAssertGreaterThan(p.object?["resident_bytes"]?.integer ?? 0, 0)
    }
    func testNativeArtifactExclusiveWriteDoesNotOverwrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-exclusive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("out.sns")
        let s = context().snapshot
        try await ArtifactWorker.shared.save(s, to: output, replaceExisting: false)
        let before = try Data(contentsOf: output)
        do { try await ArtifactWorker.shared.save(s, to: output, replaceExisting: false); XCTFail("Overwrote an existing output") }
        catch {}
        XCTAssertEqual(try Data(contentsOf: output), before)
    }
    func testPrivateSocketAuthenticatesAndCleansUp() async throws {
        let bundle = "unit." + UUID().uuidString
        let server = try LocalControlServer(bundleID: bundle) { r in ControlResponse(id: r.id, result: .object(["command": .string(r.command)])) }
        defer { server.stop() }
        let descriptors = try FileManager.default.contentsOfDirectory(atPath: LocalControlServer.directory).filter { $0.hasSuffix(".json") }
        let descriptor = try XCTUnwrap(descriptors.compactMap { name -> [String: JSONValue]? in
            let path = LocalControlServer.directory + "/" + name
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let value = try? JSONDecoder().decode(JSONValue.self, from: data), value.object?["bundle_id"]?.string == bundle else { return nil }
            return value.object
        }.first)
        let path = try XCTUnwrap(descriptor["socket"]?.string)
        let token = try XCTUnwrap(descriptor["token"]?.string)
        // Discovery connects and closes without sending. A reply to that closed peer must never terminate the app.
        try Self.probe(path: path)
        let valid = try await Task.detached { try Self.call(path: path, token: token) }.value
        XCTAssertEqual(valid.result?.object?["command"], .string("ping"))
        let invalid = try await Task.detached { try Self.call(path: path, token: "wrong") }.value
        XCTAssertEqual(invalid.error?.code, "unauthorized")
        var info = stat(); XCTAssertEqual(lstat(path, &info), 0); XCTAssertEqual(info.st_mode & 0o777, 0o600)
        server.stop(); XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
    private static func probe(path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(fd) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8CString.map { UInt8(bitPattern: $0) }) }
        let result = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { throw ControlError("test", "probe failed") }
    }
    private static func call(path: String, token: String) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(fd) }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8CString.map { UInt8(bitPattern: $0) }) }
        let connected = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else { throw ControlError("test", "connect failed") }
        var data = try JSONEncoder().encode(ControlRequest(id: .int(42), token: token, command: "ping")); data.append(10)
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
        var response = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while !response.contains(10) { let n = Darwin.read(fd, &buffer, buffer.count); guard n > 0 else { throw ControlError("test", "read failed") }; response.append(contentsOf: buffer[..<n]) }
        return try JSONDecoder().decode(ControlResponse.self, from: response)
    }
}
