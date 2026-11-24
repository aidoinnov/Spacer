import Foundation
import XCTest
@testable import SpaceSnifferCore

/// Static native age contracts, not results captured from a running Windows app.
final class FilterBoundaryFollowupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(age: TimeInterval) -> ScanSnapshot {
        let root = DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true,
                            logicalBytes: 1, allocatedBytes: 4096, children: [1])
        var file = DiskNode(id: 1, parent: 0, path: "/r/a.bin", name: "a.bin", logicalBytes: 1,
                            allocatedBytes: 4096, modified: now.addingTimeInterval(-age))
        file.created = file.modified; file.accessed = file.modified
        return ScanSnapshot(rootPath: "/r", nodes: [root, file])
    }

    func testDiscardedEmptySemicolonTokensKeepEmptyDirectoryMembership() throws {
        // Constructor 0x43f450 inserts only nonempty trimmed segments into the
        // filter list. Empty directory membership must not change for "; ;".
        var s = snapshot(age: 1)
        s.nodes[0].children.append(2)
        s.nodes.append(DiskNode(id: 2, parent: 0, path: "/r/empty", name: "empty", isDirectory: true))
        for text in ["", " ", ";", "; ;\n;", ";;"] {
            let filter = try ScanFilter(text)
            XCTAssertTrue(filter.isEmpty, text)
            XCTAssertEqual(filter.matchingIDs(in: s), [0, 1, 2], text)
        }
        XCTAssertFalse(try ScanFilter(";*.bin;;").isEmpty)
        XCTAssertFalse(try ScanFilter("|").isEmpty)
    }

    func testAgeLimitsDoNotRoundSubsecondValuesIntoInclusiveBoundary() throws {
        // isMinMaxAge 0x440810: seconds * 10,000,000; isIncluded 0x444870:
        // native maximum < unsigned(now - timestamp) rejects the node.
        for field in ["", "creation", "accessed", "modified"] {
            let maximum = try ScanFilter(field + "<1s")
            let minimum = try ScanFilter(field + ">1s")
            for age in [0.75, 1, 1.25] {
                let s = snapshot(age: age)
                XCTAssertEqual(maximum.matches(s.nodes[1], snapshot: s, now: now), age <= 1, "\(field) age \(age)")
                XCTAssertEqual(minimum.matches(s.nodes[1], snapshot: s, now: now), age >= 1, "\(field) age \(age)")
            }
        }
    }

    func testZeroAgeDisablesOnlyItsDirectionAndFirstRepeatedBoundStillWins() throws {
        // 0x444870 checks each age bound != 0 before applying it. Size bounds
        // instead use -1 as their disabled sentinel and retain a real <0b.
        for text in ["<0s", ">0s", "creation<0s;accessed>0s", "<0s;<1s"] {
            let filter = try ScanFilter(text)
            XCTAssertFalse(filter.isTimeDependent, text)
            for age in [-1, 0, 0.25, 2] {
                let s = snapshot(age: age)
                XCTAssertTrue(filter.matches(s.nodes[1], snapshot: s, now: now), "\(text) age \(age)")
            }
        }
        let s = snapshot(age: 2)
        XCTAssertFalse(try ScanFilter("<1s;<0s").matches(s.nodes[1], snapshot: s, now: now))
        XCTAssertFalse(try ScanFilter("<0s;>3s").matches(s.nodes[1], snapshot: s, now: now))
        XCTAssertTrue(try ScanFilter("<0s;>2s").matches(s.nodes[1], snapshot: s, now: now))
        XCTAssertFalse(try ScanFilter("logicalsize<0b").matches(s.nodes[1], snapshot: s, now: now))
        XCTAssertTrue(try ScanFilter("<0s;>1s").isTimeDependent)
    }

    func testOrdinaryFutureDateRetainsUnsignedAgeContract() throws {
        let s = snapshot(age: -0.25)
        XCTAssertFalse(try ScanFilter("<1s").matches(s.nodes[1], snapshot: s, now: now))
        XCTAssertTrue(try ScanFilter(">1s").matches(s.nodes[1], snapshot: s, now: now))
    }

    func testWildcardTreatsNewlinesAsFilenameBytesAndRequiresActualEnd() throws {
        // Native matches 0x445370 recurses over char* until NUL. Newlines are
        // not special anchors or forbidden characters in this matcher.
        var s = snapshot(age: 1)
        var file = s.nodes[1]; file.name = "a\nb.bin"; file.path = "/r/" + file.name; s.nodes[1] = file
        XCTAssertTrue(try ScanFilter("a?b.bin").matches(file, snapshot: s))
        XCTAssertTrue(try ScanFilter("a*b.bin").matches(file, snapshot: s))
        XCTAssertTrue(try ScanFilter("*.bin").matches(file, snapshot: s))
        file.name = "a\n"; file.path = "/r/" + file.name; s.nodes[1] = file
        XCTAssertFalse(try ScanFilter("a").matches(file, snapshot: s))
        XCTAssertTrue(try ScanFilter("a?").matches(file, snapshot: s))
        file.name = "a\r\nb"; file.path = "/r/" + file.name; s.nodes[1] = file
        XCTAssertTrue(try ScanFilter("a??b").matches(file, snapshot: s))
    }

    func testASCIIWildcardMatrixAgreesWithNativeByteRecursion() throws {
        // Independent ASCII oracle from 0x445370 + outer ASCII LowerCase in
        // 0x445050. It is not the production ICU regex or its ASCII shortcut.
        func native(_ name: [UInt8], _ pattern: [UInt8], _ n: Int = 0, _ p: Int = 0) -> Bool {
            guard p < pattern.count else { return n == name.count }
            switch pattern[p] {
            case 42: return (n...name.count).contains { native(name, pattern, $0, p + 1) }
            case 63: return n < name.count && native(name, pattern, n + 1, p + 1)
            default: return n < name.count && name[n] == pattern[p] && native(name, pattern, n + 1, p + 1)
            }
        }
        let names = ["a", "A", "ab", "a\n", "a\rb", "a\r\nb", "a\nb.bin", "a.bin", "\n", "x.a"]
        let patterns = ["*", "?", "a", "a*", "*a", "a?", "*?*", "a*b", "a??b", "a*b*", "*.*", "*.bin", "a?b.bin"]
        var s = snapshot(age: 1)
        for pattern in patterns {
            let filter = try ScanFilter(pattern)
            for name in names {
                var file = s.nodes[1]; file.name = name; file.path = "/r/" + name; s.nodes[1] = file
                let expected = native(Array(name.lowercased().utf8), Array(pattern.utf8))
                XCTAssertEqual(filter.matches(file, snapshot: s), expected, "pattern \(pattern.debugDescription), name \(name.debugDescription)")
            }
        }
    }
}
