import XCTest
@testable import SpaceSnifferCore

final class ConfiguredReportTests: XCTestCase {
    private func fixture() -> ScanSnapshot {
        ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 30, allocatedBytes: 30, children: [2,1,3]),
            DiskNode(id: 1, parent: 0, path: "/r/a.txt", name: "a.txt", logicalBytes: 10, allocatedBytes: 10),
            DiskNode(id: 2, parent: 0, path: "/r/b.txt", name: "b.txt", logicalBytes: 10, allocatedBytes: 10),
            DiskNode(id: 3, parent: 0, path: "/r/c.txt", name: "c.txt", logicalBytes: 10, allocatedBytes: 10)])
    }
    private func render(_ config: NativeConfiguration.ExportConfiguration, budget: Int64 = 1_000_000, control: ScanControl? = nil,
                        formatting: ConfiguredReport.Formatting = .init()) throws -> (String, ConfiguredReport.Statistics) {
        var sink = ArtifactDataSink()
        let stats = try ConfiguredReport.write(fixture(), configuration: config, filter: ScanFilter(""), formatting: formatting,
            maximumOutputBytes: budget, control: control, to: &sink)
        return (String(decoding: sink.value, as: UTF8.self), stats)
    }
    func testEqualIncomingChildrenPrecedeExistingChildrenRegardlessOfNodeID() throws {
        let expected = "/r/c.txt\n/r/a.txt\n/r/b.txt\n"
        XCTAssertEqual(Report.simpleFileList(fixture(), ids: [0,1,2,3], weights: [30,10,10,10]), expected)
        XCTAssertEqual(try render(.simpleFileList).0, expected)
        XCTAssertEqual(try render(.init(description: "none", detail: "{if{<%isfile%>}=={true}?{<%file%>{&br}}}")).0,
            "b.txt\na.txt\nc.txt\n")
        XCTAssertEqual(try render(.init(description: "name", detail: "{if{<%isfile%>}=={true}?{<%file%>{&br}}}", fineSorting: "name", direction: "asc")).0,
            "a.txt\nb.txt\nc.txt\n")
    }
    func testBinaryHeaderDetailFooterAndLocalCounterOrder() throws {
        let (text, stats) = try render(.init(description: "counters", header: "H<%count%>,<%foldercount%>{&br}",
            detail: "<%file%>:<%count%>,<%filecount%>,<%localcount%>{&br}", footer: "F<%count%>,<%foldercount%>,<%filecount%>{&br}"))
        XCTAssertEqual(text, "H1,1\nr:1,0,0\nb.txt:2,1,1\na.txt:3,2,2\nc.txt:4,3,3\nF5,2,3\n")
        XCTAssertEqual(stats.nodes, 4); XCTAssertEqual(stats.files, 3); XCTAssertEqual(stats.folders, 1)
        XCTAssertEqual(stats.bytes, Int64(text.utf8.count))
    }
    func testBinaryFileTagMeansFullNameAndPathDoesNotAppendASeparator() throws {
        XCTAssertEqual(try render(.init(description: "tags", detail: "{if{<%isfile%>}=={true}?{<%file%>|<%filename%>|<%fileext%>|<%path%>{&br}}}")).0,
            "b.txt|b|txt|/r\na.txt|a|txt|/r\nc.txt|c|txt|/r\n")
    }
    func testNativeSizeDescriptionRemainderUsesPreviousShiftedUnit() {
        for (bytes, expected) in [(0,"0b"),(1023,"1023b"),(1024,"1KB"),(1025,"1.0KB"),(1536,"1.5KB"),(2047,"1.9KB"),(1_048_577,"1MB")] {
            XCTAssertEqual(ConfiguredReport.describeSize(Int64(bytes)), expected)
        }
    }
    func testCallerFormattingAndMacExecutionBoundaries() throws {
        let config = NativeConfiguration.ExportConfiguration(description: "dates", detail: "{if{<%isfile%>}=={true}?{<%filemodifydate%>{&br}}}")
        XCTAssertThrowsError(try render(config))
        XCTAssertEqual(try render(config, formatting: .init(time: { _,_,_,_ in "DATE" })).0, "DATE\nDATE\nDATE\n")
        XCTAssertThrowsError(try render(.simpleFileList, budget: 1))
        XCTAssertThrowsError(try render(.simpleFileList, budget: -1))
        XCTAssertThrowsError(try render(.init(description: "sort", fineSorting: "guessed")))
        let cancelled = ScanControl(); cancelled.cancel()
        XCTAssertThrowsError(try render(.simpleFileList, control: cancelled)) { XCTAssertTrue($0 is CancellationError) }
    }
}
