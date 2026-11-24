import XCTest
@testable import SpaceSnifferCore

final class LegacySNSCodePageTests: XCTestCase {
    // Independent v2 layout: version/type, ANSI-name Base64 length+bytes,
    // logical i64, signed allocation delta i32, attributes, three FILETIMEs,
    // tag/flags, 01 00 group end. 0x4093c0 and decodeLegacy chain.
    private func bytes(_ encodedName: String, delta: Int32 = 10) -> Data {
        var data = Data([2, 3])
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let name = Data(encodedName.utf8)
        append(UInt32(name.count)); data.append(name)
        append(Int64(10)); append(delta); append(UInt32(0x10))
        for _ in 0..<3 { append(UInt64(0)) }
        data.append(contentsOf: [4, 0, 1, 0])
        return data
    }
    func testASCIIAndWhitespaceNeedNoLocaleGuessAndRoundTripToV4() throws {
        let snapshot = try SNSSnapshot.decode(bytes("Qzpc\r\ncm9vdA=="))
        XCTAssertEqual(snapshot.rootPath, "C:\\root")
        XCTAssertEqual(snapshot.nodes[0].logicalBytes, 10)
        XCTAssertEqual(snapshot.nodes[0].allocatedBytes, 20)
        XCTAssertEqual(snapshot.tags["C:\\root"], 4)
        let v4 = try SNSSnapshot.encode(snapshot)
        XCTAssertEqual(v4.first, 4)
        XCTAssertEqual(try SNSSnapshot.decode(v4).nodes[0].path, "C:\\root")
    }
    func testNonASCIIRequiresOriginalWindowsCodePage() throws {
        // Literal independent CP1252 bytes 43 3a 5c 63 61 66 e9.
        let input = bytes("QzpcY2Fm6Q==", delta: -1)
        XCTAssertThrowsError(try SNSSnapshot.decode(input)) { error in
            guard case SNSSnapshot.FormatError.legacyCodePageRequired = error else { return XCTFail("\(error)") }
        }
        let result = try SNSSnapshot.decode(input, legacyCodePage: 1252)
        XCTAssertEqual(result.rootPath, "C:\\café")
        XCTAssertEqual(result.nodes[0].allocatedBytes, 9)
        XCTAssertEqual(try SNSSnapshot.decode(SNSSnapshot.encode(result)).rootPath, result.rootPath)
        XCTAssertThrowsError(try SNSSnapshot.decode(input, legacyCodePage: 0xffff))
    }
    func testBadLegacyPayloadAndImpossibleAllocationRemainRejected() {
        XCTAssertThrowsError(try SNSSnapshot.decode(bytes("Qz!pcY2Fm6Q=="), legacyCodePage: 1252))
        XCTAssertThrowsError(try SNSSnapshot.decode(bytes("Qzpccm9vdA==", delta: -11)))
        XCTAssertThrowsError(try SNSSnapshot.decode(bytes("Qzpccm9vdA==").dropLast()))
    }
    func testMultipleTopLevelRootsPreservePathsAndRequireExplicitSelection() throws {
        let first = bytes("QzpcZmlyc3Q=") // C:\first
        let second = bytes("RDpcbmV4dA==") // D:\next
        let data = first + second
        let roots = try SNSSnapshot.decodeAll(data)
        XCTAssertEqual(roots.map(\.rootPath), ["C:\\first", "D:\\next"])
        XCTAssertEqual(roots.map { $0.nodes[0].id }, [0, 0])
        XCTAssertTrue(roots.allSatisfy { $0.nodes[0].parent == nil })
        XCTAssertThrowsError(try SNSSnapshot.decode(data)) { error in
            guard case SNSSnapshot.FormatError.rootSelectionRequired(2) = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try SNSSnapshot.decode(data, rootIndex: 1).rootPath, "D:\\next")
        XCTAssertThrowsError(try SNSSnapshot.decode(data, rootIndex: 2))
        XCTAssertThrowsError(try SNSSnapshot.decode(data, rootIndex: -1))
        let v4 = try SNSSnapshot.encode(roots: roots)
        XCTAssertEqual(try SNSSnapshot.decodeAll(v4).map(\.rootPath), roots.map(\.rootPath))
        // Never hide a corrupt second root by returning only the valid first one.
        XCTAssertThrowsError(try SNSSnapshot.decode(first + second.dropLast(), rootIndex: 0))
    }
}
