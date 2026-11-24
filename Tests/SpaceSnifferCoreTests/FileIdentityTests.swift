import XCTest
@testable import SpaceSnifferCore

final class FileIdentityTests: XCTestCase {
    private struct Legacy: Codable { var identity: String? }
    private struct Wrapped: Codable { @FileIdentity var identity: String? = nil }

    func testLegacyOptionalWireShapeAndExactSpellingArePreserved() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let values: [String?] = [nil, "", "1:2", "-16777224:18446744073709551615", "+1:2", "01:002", "-0:0",
                                 "device:inode-한글", "cafe\u{301}", "café", "1:18446744073709551616"]
        for value in values {
            let legacy = try encoder.encode(Legacy(identity: value))
            let wrapped = Wrapped(identity: value)
            XCTAssertEqual(try encoder.encode(wrapped), legacy)
            let decoded = try JSONDecoder().decode(Wrapped.self, from: legacy)
            XCTAssertEqual(decoded.identity.map { Array($0.utf8) }, value.map { Array($0.utf8) })
        }
        XCTAssertNil(try JSONDecoder().decode(Wrapped.self, from: Data("{}".utf8)).identity)
        XCTAssertNil(try JSONDecoder().decode(Wrapped.self, from: Data("{\"identity\":null}".utf8)).identity)
        XCTAssertThrowsError(try JSONDecoder().decode(Wrapped.self, from: Data("{\"identity\":123}".utf8)))
    }

    func testNativeStorageEqualsCanonicalLegacyValueAndDiskNodeRoundTrips() throws {
        var node = DiskNode(id: 0, parent: nil, path: "/fixture", name: "fixture")
        node.setNativeFileIdentity(device: -16777224, inode: UInt64.max)
        XCTAssertEqual(node.fileIdentity, "-16777224:18446744073709551615")
        var legacy = node; legacy.fileIdentity = "-16777224:18446744073709551615"
        XCTAssertEqual(node, legacy)
        XCTAssertEqual(Set([FileIdentity(device: 1, inode: 2), FileIdentity(wrappedValue: "1:2")]).count, 1)
        let data = try JSONEncoder().encode(node)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["fileIdentity"] as? String, node.fileIdentity)
        XCTAssertNil(object["_fileIdentity"])
        XCTAssertEqual(try JSONDecoder().decode(DiskNode.self, from: data), node)
        node.fileIdentity = nil
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any]
        XCTAssertNil(empty?["fileIdentity"])
    }
}
