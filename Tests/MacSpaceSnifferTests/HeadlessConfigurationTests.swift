import XCTest
@testable import MacSpaceSniffer
import SpaceSnifferCore

final class HeadlessConfigurationTests: XCTestCase {
    func testExplicitConfigurationArgumentsAndIndependentCodePages() throws {
        let args = ["--cli", "--scan", "/r", "--export-config", "/c.xml", "--export-config-index", "1", "--output", "/r.txt",
            "--config-legacy-code-page", "949", "--config-xml-code-page", "65001", "--max-output-bytes", "123"]
        let request = try HeadlessConfiguration.parse(args)
        XCTAssertEqual(request.export, "/c.xml"); XCTAssertEqual(request.index, 1); XCTAssertEqual(request.legacyCodePage, 949)
        XCTAssertEqual(request.xmlTextCodePage, 65001); XCTAssertEqual(request.maximumOutputBytes, 123)
        XCTAssertNil(try HeadlessConfiguration.parse(["--cli", "--scan", "/r"]).export)
        for bad in [["--inspect-config"], ["--inspect-config", "a", "--export-config", "b"], ["--export-config", "a"],
                    ["--export-config", "a", "--output", "a.sns"], ["--export-config-index", "0"],
                    ["--config-legacy-code-page", "0"], ["--config-xml-code-page", "65001"], ["--max-output-bytes", "-1"]] {
            XCTAssertThrowsError(try HeadlessConfiguration.parse(bad), "\(bad)")
        }
    }
    func testInspectionJSONExposesScriptsWithoutApplyingSettings() throws {
        let xml = try NativeConfiguration(exportConfigurations: [.simpleFileList]).encodedXML()
        let data = try HeadlessConfiguration.inspectionJSON(ConfigurationFile.inspect(xml))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(result["requires_export_index"] as? Bool, true)
        let exports = try XCTUnwrap(result["exports"] as? [[String: Any]])
        XCTAssertEqual(exports[0]["detail"] as? String, NativeConfiguration.ExportConfiguration.simpleFileList.detailFormat)
        XCTAssertNotNil(result["settings"]); XCTAssertNotNil(result["file_classes"])
    }
}
