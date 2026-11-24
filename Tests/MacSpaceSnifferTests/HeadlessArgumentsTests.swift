import XCTest
@testable import MacSpaceSniffer

final class HeadlessArgumentsTests: XCTestCase {
    func testRejectsAmbiguousOrIncompleteCommands() {
        for args in [["--cli", "--scan", "/r", "--unknown"],
                     ["--cli", "--scan", "/r", "--filter"],
                     ["--cli", "--scan", "/r", "--filter", "--logical"],
                     ["--cli", "--scan", "/r", "--scan", "/r"],
                     ["--cli", "--scan", "/r", "--load", "/s"],
                     ["--cli", "--scan", "/r", "--legacy-code-page", "949"],
                     ["--cli", "--load", "/s", "--list-roots", "--output", "/o.sns"],
                     ["--cli", "--inspect-config", "/c", "--filter", "*.txt"],
                     ["--cli", "stray"]] {
            XCTAssertThrowsError(try HeadlessArguments(args), "\(args)")
        }
    }
    func testValuesMayContainSpacesUnicodeOrBeAnEmptyFilter() throws {
        let request = try HeadlessArguments(["--cli", "--scan", "/tmp/한글 folder", "--filter", "", "--logical"])
        XCTAssertEqual(request.value("--scan"), "/tmp/한글 folder")
        XCTAssertEqual(request.value("--filter"), "")
        XCTAssertTrue(request.switches.contains("--logical"))
        XCTAssertNoThrow(try HeadlessArguments(["--cli", "--inspect-config", "/config.xml"]))
    }
}
