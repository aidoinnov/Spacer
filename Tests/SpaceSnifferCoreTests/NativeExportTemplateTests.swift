import XCTest
@testable import SpaceSnifferCore

final class NativeExportTemplateTests: XCTestCase {
    func testNativeSimplePresetAndBinaryTagCase() throws {
        let source = "{ if {<%isfile%>} == {true} ? {<%pathfile%>{&br}}}"
        let template = try NativeExportTemplate(source)
        XCTAssertEqual(template.referencedTags, ["isfile", "pathfile"])
        XCTAssertEqual(try template.render(values: ["isfile":"true", "pathfile":"C:\\한글\\a.txt"]), "C:\\한글\\a.txt\n")
        XCTAssertEqual(try template.render(values: ["isfile":"false"]), "")
        XCTAssertEqual(try NativeExportTemplate("<%FILE%>|<%unknown%>|<%file%>").render(values: [:]), "*BAD TAG*|*BAD TAG*|*VOID*")
    }
    func testScriptModeRemovesOnlyObservedCRLFPairsAndTabs() throws {
        let template = try NativeExportTemplate(" \r\n {script} A\r\n\tB\nC ")
        XCTAssertEqual(try template.render(values: [:]), " AB\nC ")
        XCTAssertEqual(try NativeExportTemplate("a\t\r\nb").render(values: [:]), "a\t\r\nb")
        XCTAssertEqual(try NativeExportTemplate("head{script}tail").render(values: [:]), "headscripttail")
    }
    func testNativeCommandsPaddingTruncationAndNesting() throws {
        XCTAssertEqual(try NativeExportTemplate("{leftpad{abc}{xy}{6}}").render(values: [:]), "yxyabc")
        XCTAssertEqual(try NativeExportTemplate("{rightpad{abc}{xy}{6}}").render(values: [:]), "abcxyx")
        XCTAssertEqual(try NativeExportTemplate("{leftpad{abcdef}{ }{3}}").render(values: [:]), "def")
        XCTAssertEqual(try NativeExportTemplate("{rightpad{abcdef}{ }{3}}").render(values: [:]), "abc")
        XCTAssertEqual(try NativeExportTemplate("{nest{ab}}").render(values: [:], nestingLevel: 3), "ababab")
        XCTAssertEqual(try NativeExportTemplate("{&curlyop}{&curlycl}{&angleop}{&anglecl}{&tab}").render(values: [:]), "{}<>\t")
        XCTAssertEqual(try NativeExportTemplate("{rightpad{A}{if{0}=={1}?{x}}{4}}").render(values: [:]), "A*BA")
        XCTAssertEqual(try NativeExportTemplate("{leftpad{A}{}{3}}").render(values: [:]), "leftpadA3", "Empty parsed groups are omitted by native atomizeFormatRecourse")
    }
    func testEqualityUsesExactUTF16WhileRelationalComparisonTriesNumbers() throws {
        XCTAssertEqual(try NativeExportTemplate("{if{01}=={1}?{yes}:{no}}").render(values: [:]), "no")
        XCTAssertEqual(try NativeExportTemplate("{if{01}<={1}?{yes}:{no}}").render(values: [:]), "yes")
        XCTAssertEqual(try NativeExportTemplate("{if{ab}<{b}?{yes}:{no}}").render(values: [:]), "yes")
        XCTAssertEqual(try NativeExportTemplate("{if{é}=={e\u{301}}?{yes}:{no}}").render(values: [:]), "no")
        XCTAssertEqual(try NativeExportTemplate("{if{1,5}<{2}?{yes}:{no}}").render(values: [:], decimalSeparator: ","), "yes")
        XCTAssertEqual(try NativeExportTemplate("{if{a}=={a}?{{if{2}>{1}?{nested}:{wrong}}}:{else}}").render(values: [:]), "nested")
    }
    func testPreviewFileBreakAndObservedGenericAtomFallback() throws {
        let template = try NativeExportTemplate("{&br}")
        XCTAssertEqual(try template.render(values: [:], lineBreaks: .preview), "\r\n")
        XCTAssertEqual(try template.render(values: [:], lineBreaks: .fileText), "\n")
        XCTAssertEqual(try NativeExportTemplate("&br").render(values: [:]), "\n")
        XCTAssertEqual(try NativeExportTemplate("{plain{text}}").render(values: [:]), "plaintext")
        XCTAssertEqual(try NativeExportTemplate("unfinished <%file").render(values: [:]), "unfinished <%file")
    }
    func testMacExecutionBoundariesAndCooperativeCancellation() throws {
        XCTAssertThrowsError(try NativeExportTemplate("12345", limits: .init(inputUTF16: 4)))
        XCTAssertThrowsError(try NativeExportTemplate("{{{{x}}}}", limits: .init(nesting: 2)))
        XCTAssertThrowsError(try NativeExportTemplate("{x}{y}", limits: .init(atoms: 2)))
        XCTAssertThrowsError(try NativeExportTemplate("{unclosed"))
        XCTAssertThrowsError(try NativeExportTemplate("<%file%>", limits: .init(outputUTF16: 4)).render(values: ["file":"12345"]))
        XCTAssertThrowsError(try NativeExportTemplate("{rightpad{x}{ }{2147483647}}").render(values: [:]))
        XCTAssertThrowsError(try NativeExportTemplate("12345", limits: .init(workUTF16: 8)).render(values: [:]))
        let control = ScanControl(); control.cancel()
        XCTAssertThrowsError(try NativeExportTemplate("x", control: control)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try NativeExportTemplate("x").render(values: [:], control: control)) { XCTAssertTrue($0 is CancellationError) }
    }
    func testManyAtomFallbackKeepsUTF16AndWorkBoundaries() throws {
        let atom = "🙂e\u{301}", source = String(repeating: "{" + atom + "}", count: 2048)
        let expected = String(repeating: atom, count: 2048), units = expected.utf16.count
        XCTAssertEqual(try NativeExportTemplate(source, limits: .init(outputUTF16: units)).render(values: [:]), expected)
        XCTAssertThrowsError(try NativeExportTemplate(source, limits: .init(outputUTF16: units - 1)).render(values: [:])) {
            XCTAssertEqual($0 as? NativeExportTemplate.TemplateError, .outputLimit)
        }
        XCTAssertThrowsError(try NativeExportTemplate(source, limits: .init(workUTF16: source.utf16.count)).render(values: [:])) {
            XCTAssertEqual($0 as? NativeExportTemplate.TemplateError, .workLimit)
        }
    }
}
