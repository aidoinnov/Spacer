import XCTest
@testable import SpaceSnifferCore

final class NativeConfigurationTests: XCTestCase {
    private func bytes(_ xml: String) -> Data { Data(xml.utf8) }
    private func encodedFormat(_ value: String, version: Int) -> String {
        (version == 3 ? value.data(using: .utf16LittleEndian)! : Data(value.utf8)).base64EncodedString()
    }
    func testDefaultsAndExactBooleanAndScalarKeys() throws {
        let defaults = try NativeConfiguration.decode(bytes("<SpaceSnifferConfig/>"))
        XCTAssertEqual(defaults, NativeConfiguration())
        XCTAssertEqual(defaults.settings["zoomTimeMs"], .integer(5)); XCTAssertEqual(defaults.settings["initialDetailLevel"], .integer(3))
        XCTAssertEqual(defaults.fileClasses.count, 5)
        let xml = "<SpaceSnifferConfig><refreshDelayMs>12</refreshDelayMs><refreshDelayMs>13</refreshDelayMs><showFreeSpace>true</showFreeSpace><useSorting>TRUE</useSorting><initialStyle>other</initialStyle><colors><fileColor>$FFAABB</fileColor><levelContrast> 10.9 </levelContrast><borderContrast>-2.7</borderContrast><mouseHover>false</mouseHover></colors><ignored>anything</ignored></SpaceSnifferConfig>"
        let parsed = try NativeConfiguration.decode(bytes(xml))
        XCTAssertEqual(parsed.settings["refreshDelayMs"], .integer(13))
        XCTAssertEqual(parsed.settings["showFreeSpace"], .boolean(true)); XCTAssertEqual(parsed.settings["useSorting"], .boolean(false))
        XCTAssertEqual(parsed.settings["initialStyle"], .text("fileClasses")); XCTAssertEqual(parsed.settings["colors.fileColor"], .integer(0xffaabb))
        XCTAssertEqual(parsed.settings["colors.levelContrast"], .decimal(10)); XCTAssertEqual(parsed.settings["colors.borderContrast"], .decimal(-2))
        XCTAssertNil(parsed.settings["ignored"])
    }
    func testAbsentAndExplicitlyEmptyFileGroupsHaveDifferentMeaning() throws {
        XCTAssertEqual(try NativeConfiguration.decode(bytes("<config/>")).fileClasses.count, 5)
        XCTAssertTrue(try NativeConfiguration.decode(bytes("<config><fileGroups/></config>")).fileClasses.isEmpty)
        let parsed = try NativeConfiguration.decode(bytes("<config><fileGroups><fileGroup><name>Custom</name><extensions>jpg; \"a;b\";\"a\"\"b\";;txt;</extensions><color>255</color></fileGroup><fileGroup/></fileGroups></config>"))
        XCTAssertEqual(parsed.fileClasses.map(\.name), ["Custom", "???"])
        XCTAssertEqual(parsed.fileClasses[0].extensions, ["jpg","a;b","a\"b","","txt",""])
        XCTAssertEqual(parsed.fileClasses[0].color, 255); XCTAssertEqual(parsed.fileClasses[1].extensions, [])
    }
    func testVersion3UTF16ScriptsAndVersion1ConversionAreDistinct() throws {
        let script = "한글🙂 <%size%> <%sizebytes%>"
        let modern = try NativeConfiguration.decodeExportConfiguration(bytes("<exportConfig version=\"3\"><description>Custom</description><detailFormat>\(encodedFormat(script,version:3))</detailFormat></exportConfig>"))
        XCTAssertEqual(modern.detailFormat, script); XCTAssertEqual(modern.sourceVersion, 3)
        let oldText = "<%size%>|<%sizebytes%>|<%disksize%>"
        let old = try NativeConfiguration.decodeExportConfiguration(bytes("<exportConfig version=\"1\"><detailFormat>\(encodedFormat(oldText,version:1))</detailFormat></exportConfig>"))
        XCTAssertEqual(old.detailFormat, "<%disksize%>|<%disksizebytes%>|<%disksize%>")
        let absentVersion = try NativeConfiguration.decodeExportConfiguration(bytes("<exportConfig><detailFormat>\(encodedFormat(oldText,version:1))</detailFormat></exportConfig>"))
        XCTAssertEqual(absentVersion.sourceVersion, 0); XCTAssertEqual(absentVersion.detailFormat, oldText)
        let two = try NativeConfiguration.decodeExportConfiguration(bytes("<exportConfig version=\"2\"><detailFormat>\(encodedFormat(oldText,version:2))</detailFormat></exportConfig>"))
        XCTAssertEqual(two.detailFormat, oldText)
    }
    func testExplicitCodePagesAndXMLTextAreNotGuessed() throws {
        let legacyPayload = Data([0xe9]).base64EncodedString()
        let xml = bytes("<exportConfig version=\"2\"><detailFormat>\(legacyPayload)</detailFormat></exportConfig>")
        XCTAssertThrowsError(try NativeConfiguration.decodeExportConfiguration(xml))
        XCTAssertEqual(try NativeConfiguration.decodeExportConfiguration(xml,legacyCodePage:1252).detailFormat, "é")
        let textXML = bytes("<exportConfig version=\"3\"><description>한글</description></exportConfig>")
        XCTAssertThrowsError(try NativeConfiguration.decodeExportConfiguration(textXML))
        XCTAssertEqual(try NativeConfiguration.decodeExportConfiguration(textXML,xmlTextCodePage:65001).description, "한글")
        XCTAssertEqual(try WindowsLegacyText.decode(Data([0xc7,0xd1]), codePage: 949), "한")
        XCTAssertThrowsError(try WindowsLegacyText.decode(Data([0xe9]), codePage: 99999))
    }
    func testNativeVersion3EncodingRoundtripAndEmptyDescriptionSortBarriers() throws {
        let source = NativeConfiguration(settings: ["fontSize":.integer(9)], fileClasses: [.init(name:"한글",extensions:"bin;txt",color:42)], exportConfigurations: [
            .init(description:"z",detail:"<%pathfile%>"), .init(description:"a",detail:"첫째"), .init(description:"",detail:"barrier"),
            .init(description:"y",detail:"last"), .init(description:"b",detail:"other")])
        let xml = try source.encodedXML(); XCTAssertTrue(String(decoding:xml,as:UTF8.self).contains("version=\"3\""))
        let parsed = try NativeConfiguration.decode(xml,xmlTextCodePage:65001)
        XCTAssertEqual(parsed.settings["fontSize"], .integer(9)); XCTAssertEqual(parsed.fileClasses, source.fileClasses)
        XCTAssertEqual(parsed.exportConfigurations.map(\.description), ["a","z","","b","y"])
        XCTAssertEqual(parsed.exportConfigurations[0].detailFormat, "첫째")
        let export = try NativeConfiguration.decodeExportConfiguration(NativeConfiguration.ExportConfiguration.simpleFileList.encodedXML())
        XCTAssertEqual(export, .simpleFileList)
    }
    func testMalformedEncodingEntitiesAndBudgetsFailWithoutExternalIO() throws {
        for xml in ["<config>","<!DOCTYPE x SYSTEM \"http://example.invalid/a\"><x/>","<!DOCTYPE x [<!ENTITY a 'expansion'>]><x>&a;</x>","<exportConfig version=\"0\"/>","<exportConfig version=\"4\"/>","<exportConfig version=\"3\"><detailFormat>%%%invalid</detailFormat></exportConfig>","<exportConfig version=\"3\"><detailFormat>QQ==</detailFormat></exportConfig>"] {
            XCTAssertThrowsError(try NativeConfiguration.decodeExportConfiguration(bytes(xml)))
        }
        XCTAssertThrowsError(try NativeConfiguration.decode(Data(repeating:32,count:4_194_305)))
        XCTAssertThrowsError(try NativeConfiguration.decode(bytes(String(repeating:"<a>",count:257)+String(repeating:"</a>",count:257))))
        let control=ScanControl();control.cancel()
        XCTAssertThrowsError(try NativeConfiguration.decode(bytes("<config/>"),control:control)) { XCTAssertTrue($0 is CancellationError) }
    }
    func testFullXMLByteLimitIncludesClosingTagsAtExactBoundary() throws {
        func config(_ name: String) -> NativeConfiguration { NativeConfiguration(fileClasses: [.init(name: name, extensions: "", color: 0)]) }
        let overhead = try config("").encodedXML().count, capacity = 4_194_304 - overhead
        let exact = try config(String(repeating: "a", count: capacity)).encodedXML()
        XCTAssertEqual(exact.count, 4_194_304)
        XCTAssertTrue(String(decoding: exact.suffix(32), as: UTF8.self).hasSuffix("</SpaceSnifferConfig>"))
        XCTAssertThrowsError(try config(String(repeating: "a", count: capacity + 1)).encodedXML()) {
            XCTAssertEqual($0 as? NativeConfiguration.ConfigurationError, .inputLimit)
        }
    }
    func testEscapingAndUnicodeAreCountedBeforeBoundedSerialization() throws {
        let name = "한🙂&<>e\u{301}", source = NativeConfiguration(fileClasses: [.init(name: name, extensions: "a&b;<x>", color: 42)])
        let data = try source.encodedXML()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("한🙂&amp;&lt;&gt;e\u{301}"))
        XCTAssertEqual(try NativeConfiguration.decode(data, xmlTextCodePage: 65001), source)
        XCTAssertThrowsError(try NativeConfiguration(fileClasses: [.init(name: String(repeating: "&", count: 900_000), extensions: "", color: 0)]).encodedXML())
        XCTAssertThrowsError(try NativeConfiguration(settings: ["initialStyle": .text(String(repeating: "&", count: 900_000))], fileClasses: []).encodedXML())
        XCTAssertThrowsError(try NativeConfiguration.ExportConfiguration(description: String(repeating: "&", count: 900_000)).encodedXML())
    }
    func testStandaloneXMLByteLimitCountsEscapedMetadataAndDeclaration() throws {
        let overhead = try NativeConfiguration.ExportConfiguration(description: "").encodedXML().count
        let available = 4_194_304 - overhead
        let description = String(repeating: "&", count: available / 5) + String(repeating: "a", count: available % 5)
        let exact = try NativeConfiguration.ExportConfiguration(description: description).encodedXML()
        XCTAssertEqual(exact.count, 4_194_304)
        XCTAssertEqual(try NativeConfiguration.decodeExportConfiguration(exact).description, description)
        XCTAssertThrowsError(try NativeConfiguration.ExportConfiguration(description: description + "a").encodedXML())
    }
}
