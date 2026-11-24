import XCTest
@testable import SpaceSnifferCore

final class RefreshIndexTests: XCTestCase, @unchecked Sendable {
    private func assertSame(_ queue: RefreshQueue, _ legacy: LegacyRefreshQueue, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(queue.paths.map { Array($0.utf8) }, legacy.paths.map { Array($0.utf8) }, file: file, line: line)
        XCTAssertEqual(queue.isEmpty, legacy.isEmpty, file: file, line: line)
    }
    func testLexicalBoundaryMatrixAndUnicodeCanonicalEquivalence() {
        let paths = ["", "/", "\\", "/a", "/ab", "/a/", "/a//b", "/a\\x", "relative", "relative/", "a:b", "a:b\\x",
            "C:", "C:\\", "C:/", "C:\\a", "C:\\a\\", "C:\\a/b", "\\\\server\\share", "\\\\server\\share\\",
            "/café/x", "/cafe\u{301}/x", "/a/\u{301}x", "/a/👨‍👩‍👧", "/a/👨", "/a/\r\n", "/a/\r", "/a/\u{600}/x", "/a/🇰🇷", "/a/🇰", "/a/\0"]
        for first in paths {
            for second in paths {
                var queue = RefreshQueue(); var legacy = LegacyRefreshQueue()
                for id in 0..<20 { let path = "/padding-\(id)"; queue.insert(path); legacy.insert(path) }
                for path in [first, second] { queue.insert(path); legacy.insert(path); assertSame(queue, legacy) }
                queue.removeCovered(by: first); legacy.removeCovered(by: first); assertSame(queue, legacy)
                XCTAssertEqual(queue.popFirst(), legacy.popFirst()); assertSame(queue, legacy)
            }
        }
    }
    func testSeededOperationsMatchArrayOracleAtEveryStep() {
        var rng = QueueRandom(state: 0x1a2b3c4d)
        let parts = ["a", "ab", "é", "e\u{301}", "한글", "👨‍👩‍👧", "👨", "\r", "\n", "\u{301}", "\u{600}", "🇰", "🇷", "", ".", "..", ":", "\\", "/", "\0"]
        var paths: [String] = []
        for id in 0..<350 {
            var path = id % 3 == 0 ? "C:\\fuzz" : id % 3 == 1 ? "/fuzz" : "relative"
            for _ in 0..<(2 + Int(rng.next() % 4)) { path += rng.next() % 2 == 0 ? "/" : "\\"; path += parts[Int(rng.next() % UInt64(parts.count))] }
            paths.append(path)
        }
        var queue = RefreshQueue(); var legacy = LegacyRefreshQueue()
        for id in 0..<100 { let path = "/initial/\(id)/leaf"; queue.insert(path); legacy.insert(path) }
        for _ in 0..<20000 {
            let path = paths[Int(rng.next() % UInt64(paths.count))]
            switch rng.next() % 100 {
            case 0..<65: queue.insert(path); legacy.insert(path)
            case 65..<90: queue.removeCovered(by: path); legacy.removeCovered(by: path)
            case 90..<99: XCTAssertEqual(queue.popFirst(), legacy.popFirst())
            default: queue.removeAll(); legacy.removeAll()
            }
            assertSame(queue, legacy)
        }
    }
    func testRadixPrefixAndRemovalAgreeWithStringOperations() {
        let keys = ["", "a", "a\u{301}", "á/x", "a/", "a/\u{301}", "\u{600}", "\u{600}/x", "\r", "\r\n", "👨", "👨‍👩‍👧", "🇰", "🇰🇷", "/café", "/cafe\u{301}/x"]
        var index = RefreshPathIndex(); var retained: [String: Int] = [:]
        for (id, key) in keys.enumerated() { index.insert(key, id: id); retained[key] = id }
        for removal in keys.reversed() {
            for prefix in keys {
                XCTAssertEqual(index.exact(prefix), retained[prefix])
                XCTAssertEqual(index.hasPrefix(of: prefix), retained.keys.contains { prefix.hasPrefix($0) })
                XCTAssertEqual(Set(index.prefixed(by: prefix)), Set(retained.filter { $0.key.hasPrefix(prefix) }.values))
            }
            index.remove(removal); retained[removal] = nil
        }
    }
    func testCopiedQueueAndConcurrentReaderAreIsolated() async {
        var queue = RefreshQueue()
        for id in 0..<200 { queue.insert("/copy/\(id)/leaf") }
        let frozen = queue
        let reader = Task.detached { frozen.paths }
        queue.removeCovered(by: "/copy/50"); queue.insert("/copy/new")
        let expected = (0..<200).map { "/copy/\($0)/leaf" }
        let observed = await reader.value
        XCTAssertEqual(observed, expected); XCTAssertEqual(frozen.paths, expected)
        XCTAssertFalse(queue.paths.contains("/copy/50/leaf")); XCTAssertEqual(queue.paths.last, "/copy/new")
        var another = frozen; another.insert("/copy")
        XCTAssertEqual(another.paths, ["/copy"]); XCTAssertEqual(frozen.paths, expected)
    }
    func testIndexCompactsAndReleasesAllSlotsAtIdle() {
        var queue = RefreshQueue(); var legacy = LegacyRefreshQueue()
        for id in 0..<4000 { let p = "/audit/\(id)/leaf"; queue.insert(p); legacy.insert(p) }
        XCTAssertGreaterThan(queue.indexSlots, 0)
        for id in 0..<3900 { let p = "/audit/\(id)"; queue.removeCovered(by: p); legacy.removeCovered(by: p) }
        assertSame(queue, legacy); XCTAssertLessThanOrEqual(queue.indexSlots, max(128, queue.paths.count * 12))
        queue.insert("/audit"); legacy.insert("/audit"); assertSame(queue, legacy)
        XCTAssertEqual(queue.indexSlots, 0)
        while queue.popFirst() != nil {}
        XCTAssertEqual(queue.indexSlots, 0)
        for _ in 0..<50 {
            for id in 0..<64 { queue.insert("/cycle/\(id)") }
            queue.removeAll(); XCTAssertTrue(queue.isEmpty); XCTAssertEqual(queue.indexSlots, 0)
        }
    }
    func testLongPathDoesNotCreateRecursiveCharacterNodeChain() {
        let prefix = "/" + String(repeating: "a/", count: 10000)
        var queue = RefreshQueue()
        for id in 0..<20 { queue.insert(prefix + "leaf-\(id)") }
        XCTAssertLessThan(queue.indexSlots, 150)
        queue.removeCovered(by: prefix); XCTAssertTrue(queue.isEmpty); XCTAssertEqual(queue.indexSlots, 0)
    }
}
private struct QueueRandom {
    var state: UInt64
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
