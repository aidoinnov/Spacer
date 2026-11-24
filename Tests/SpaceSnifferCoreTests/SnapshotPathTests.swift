import XCTest
@testable import SpaceSnifferCore

final class SnapshotPathTests: XCTestCase {
    func testJoinPreservesRootSeparatorsAndUnicodeSpelling() {
        let cases: [(String, String, String)] = [
            ("/", "file", "/file"), ("/base", "file", "/base/file"),
            ("/base//", "file", "/base//file"), ("", "file", "/file"),
            ("/base", "", "/base/"), ("/base/", "", "/base/"),
            ("/한글🙂", "cafe\u{301}", "/한글🙂/cafe\u{301}"),
            ("C:", "file", "C:\\file"), ("C:\\", "file", "C:\\file"),
            ("C:\\base", "한글🙂", "C:\\base\\한글🙂"),
            ("\\\\server\\share\\", "file", "\\\\server\\share\\file"),
            ("C:/base/", "file", "C:/base/\\file")
        ]
        for (root, name, expected) in cases {
            XCTAssertEqual(Array(SnapshotPath.join(root, name).utf8), Array(expected.utf8))
            if !SnapshotPath.isWindows(root) {
                XCTAssertEqual(Array(SnapshotPath.joinPOSIX(root, name).utf8), Array(expected.utf8))
            }
        }
    }
}
