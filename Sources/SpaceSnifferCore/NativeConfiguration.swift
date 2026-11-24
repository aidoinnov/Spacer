import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Data codec for getConfig 0x40c420/saveConfig 0x40f000. This model does not
/// change global UI settings or eagerly create a singleton configuration.
public struct NativeConfiguration: Sendable, Equatable {
    public enum ConfigurationError: Error, Equatable { case malformedXML, inputLimit, unsupportedVersion(Int), invalidValue(String), invalidBase64, invalidUTF16 }
    public enum Value: Sendable, Equatable { case integer(Int32), boolean(Bool), decimal(Double), text(String) }
    public struct FileClass: Sendable, Equatable {
        public let name: String, extensionsText: String, extensions: [String]
        public let color: Int32
        public init(name: String, extensions: String, color: Int32) {
            self.name = name; extensionsText = extensions; self.color = color
            self.extensions = Self.delimitedExtensions(extensions)
        }
        /// TFileGroup::init 0x40b5b0: TStringList, delimiter ';', default
        /// non-strict whitespace and double-quote extraction (0x67ecb0).
        private static func delimitedExtensions(_ text: String) -> [String] {
            let units = Array(text.utf16); var i = 0, result: [String] = []
            func whitespace(_ value: UInt16) -> Bool { value > 0 && value <= 32 }
            while i < units.count, whitespace(units[i]) { i += 1 }
            while i < units.count, units[i] != 0 {
                var token: [UInt16] = []
                if units[i] == 34 {
                    i += 1
                    while i < units.count, units[i] != 0 {
                        if units[i] == 34 {
                            i += 1
                            if i < units.count, units[i] == 34 { token.append(34); i += 1; continue }
                            break
                        }
                        token.append(units[i]); i += 1
                    }
                } else {
                    while i < units.count, units[i] > 32, units[i] != 59 { token.append(units[i]); i += 1 }
                }
                result.append(String(decoding: token, as: UTF16.self))
                while i < units.count, whitespace(units[i]) { i += 1 }
                if i < units.count, units[i] == 59 {
                    i += 1
                    if i == units.count || units[i] == 0 { result.append("") }
                    while i < units.count, whitespace(units[i]) { i += 1 }
                }
            }
            return result
        }
    }
    public struct ExportConfiguration: Sendable, Equatable {
        public let description: String, preferredFileName: String, preferredFileExtension: String
        public let headerFormat: String, detailFormat: String, footerFormat: String
        public let blockSorting: String, fineSorting: String, fineSortingDirection: String
        public let sourceVersion: Int
        public init(description: String, preferredFileName: String = "", preferredFileExtension: String = "", header: String = "", detail: String = "", footer: String = "",
                    blockSorting: String = "", fineSorting: String = "", direction: String = "", sourceVersion: Int = 3) {
            self.description = description; self.preferredFileName = preferredFileName; self.preferredFileExtension = preferredFileExtension
            headerFormat = header; detailFormat = detail; footerFormat = footer
            self.blockSorting = blockSorting; self.fineSorting = fineSorting; fineSortingDirection = direction; self.sourceVersion = sourceVersion
        }
        public static let simpleFileList = ExportConfiguration(description: "Simple file list", preferredFileName: "File list", preferredFileExtension: "Text file (*.txt)|*.txt",
            detail: "{ if {<%isfile%>} == {true} ? {<%pathfile%>{&br}}}", blockSorting: "files", fineSorting: "size", direction: "desc")
        /// TExportConfig::exportTo always emits version 3 and Base64 UTF16LE.
        public func encodedXML() throws -> Data {
            var builder = XMLBuilder()
            try builder.raw("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
            try appendXML(to: &builder)
            return Data(builder.output.utf8)
        }
        fileprivate func appendXML(to builder: inout XMLBuilder) throws {
            let fields = [description,preferredFileName,preferredFileExtension,headerFormat,detailFormat,footerFormat,blockSorting,fineSorting,fineSortingDirection]
            var remaining = 1_048_576
            for field in fields {
                let count = field.utf16.prefix(remaining + 1).count
                guard count <= remaining else { throw ConfigurationError.inputLimit }
                remaining -= count
            }
            try builder.raw("<exportConfig version=\"3\">")
            for (key, value) in [("description",description),("preferredFileName",preferredFileName),("preferredFileExtension",preferredFileExtension),
                ("headerFormat",Self.encodeFormat(headerFormat)),("detailFormat",Self.encodeFormat(detailFormat)),("footerFormat",Self.encodeFormat(footerFormat)),
                ("blockSorting",blockSorting),("fineSorting",fineSorting),("fineSortingDirection",fineSortingDirection)] {
                try builder.element(key, value)
            }
            try builder.raw("</exportConfig>")
        }
        private static func encodeFormat(_ text: String) -> String { Data(text.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }).base64EncodedString() }
    }
    public private(set) var settings: [String: Value]
    public private(set) var fileClasses: [FileClass]
    public private(set) var exportConfigurations: [ExportConfiguration]
    public init(settings: [String: Value] = [:], fileClasses: [FileClass]? = nil, exportConfigurations: [ExportConfiguration] = []) {
        self.settings = Self.defaults.merging(settings, uniquingKeysWith: { _, new in new })
        self.fileClasses = fileClasses ?? Self.defaultFileClasses; self.exportConfigurations = exportConfigurations
    }
    public static let defaultFileClasses: [FileClass] = [
        FileClass(name: "Video/Movies", extensions: "qt;mov;mpeg;mpg;mpe;m1s;mp4;avi;mts;vob;wmv;rm;3gp;mkv", color: 0xff),
        FileClass(name: "Executables/System files", extensions: "exe;dll;sys;ini;msi;log", color: 0xffff),
        FileClass(name: "Archives/Disk images", extensions: "zip;7z;rar;iso", color: 0xff0000),
        FileClass(name: "Pictures/Images", extensions: "jpg;jpeg;gif;png;tif;tiff;nef;raw;rw2;cr2;bmp;psd", color: 0xff00),
        FileClass(name: "Audio/Music", extensions: "mp2;mp3;wav;ogg;aif;alp;au;3gp;ac3;amr;aac;m4a;wma;aiff;flac;m4a;voc", color: 0xc080ff)]
    private static let integerKeys = ["refreshDelayMs","zoomTimeMs","minElementSizePx","proportions","initialDetailLevel","fontSize"]
    private static let booleanKeys = ["showFreeSpace","showUnknownSpace","showFileTooltipDateTime","showFileTooltipAge","useRealZoom","useDynaSmooth","useSorting","scanADS","watchDog","logPopup","logWarning","flashElement","flashWindow","keepTooltip"]
    private static let colorIntegerKeys = ["driveColor","folderColor","fileColor","freeColor","unknownColor","hilightHaloLevels"]
    private static let colorBooleanKeys = ["mouseHover","mouseTrail","hilightShadow"]
    public static let defaults: [String: Value] = [
        "refreshDelayMs":.integer(50), "zoomTimeMs":.integer(5), "minElementSizePx":.integer(10), "proportions":.integer(0), "initialDetailLevel":.integer(3), "fontSize":.integer(7),
        "showFreeSpace":.boolean(false), "showUnknownSpace":.boolean(false), "initialStyle":.text("flat"), "showFileTooltipDateTime":.boolean(false), "showFileTooltipAge":.boolean(true),
        "useRealZoom":.boolean(false), "useDynaSmooth":.boolean(true), "useSorting":.boolean(true), "scanADS":.boolean(false), "watchDog":.boolean(true),
        "logPopup":.boolean(true), "logWarning":.boolean(true), "flashElement":.boolean(true), "flashWindow":.boolean(true), "keepTooltip":.boolean(true),
        "colors.driveColor":.integer(0x99ff), "colors.folderColor":.integer(0x99ccff), "colors.fileColor":.integer(0xffcc99), "colors.freeColor":.integer(0x8000), "colors.unknownColor":.integer(0x808080),
        "colors.levelContrast":.decimal(10), "colors.borderContrast":.decimal(30), "colors.mouseHover":.boolean(true), "colors.mouseTrail":.boolean(true), "colors.hilightShadow":.boolean(true), "colors.hilightHaloLevels":.integer(3)]
    /// xmlTextCodePage is the original runtime's UnicodeFromPChar code page,
    /// distinct from the legacy Base64 payload's source ACP. Non-ASCII never guesses.
    public static func decode(_ data: Data, legacyCodePage: UInt32? = nil, xmlTextCodePage: UInt32? = nil, control: ScanControl? = nil) throws -> NativeConfiguration {
        let root = try XMLTree.read(data, control: control)
        var result = NativeConfiguration(), groups: [FileClass] = [], exports: [ExportConfiguration] = [], sawGroups = false
        for child in root.children {
            try check(control)
            if integerKeys.contains(child.name) { result.settings[child.name] = .integer(try integer(child.text)) }
            else if booleanKeys.contains(child.name) { result.settings[child.name] = .boolean(child.text == "true") }
            else if child.name == "initialStyle" { result.settings[child.name] = .text(child.text == "flat" ? "flat" : "fileClasses") }
            else if child.name == "colors" {
                for color in child.children {
                    if colorIntegerKeys.contains(color.name) { result.settings["colors."+color.name] = .integer(try integer(color.text)) }
                    else if colorBooleanKeys.contains(color.name) { result.settings["colors."+color.name] = .boolean(color.text == "true") }
                    else if ["levelContrast","borderContrast"].contains(color.name) {
                        guard let number = Double(color.text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite, number >= Double(Int32.min), number <= Double(Int32.max) else { throw ConfigurationError.invalidValue(color.name) }
                        // getConfig explicitly stores (double)(int)getDbl, before UI positioning.
                        result.settings["colors."+color.name] = .decimal(Double(Int32(number)))
                    }
                }
            } else if child.name == "fileGroups" {
                sawGroups = true
                for group in child.children where group.name == "fileGroup" {
                    let name = try nativeText(group.last("name")?.text ?? "???", codePage: xmlTextCodePage)
                    let extensions = try nativeText(group.last("extensions")?.text ?? "", codePage: xmlTextCodePage)
                    groups.append(FileClass(name: name, extensions: extensions, color: try group.last("color").map { try integer($0.text) } ?? 0))
                }
            } else if child.name == "exportConfigs" {
                for entry in child.children where entry.name == "exportConfig" { exports.append(try exportConfiguration(entry, legacyCodePage: legacyCodePage, xmlTextCodePage: xmlTextCodePage)) }
            }
        }
        result.fileClasses = sawGroups ? groups : defaultFileClasses; result.exportConfigurations = sortedExports(exports)
        return result
    }
    /// Explicit app adapter entry: reject unrelated XML instead of emitting an empty report.
    public static func decodeExportConfigurations(_ data:Data, codePage:UInt32? = nil) throws -> [ExportConfiguration] {
        let root=try XMLTree.read(data,control:nil)
        if root.name == "exportConfig" {return [try exportConfiguration(root,legacyCodePage:codePage,xmlTextCodePage:codePage)]}
        guard root.name == "SpaceSnifferConfig" else {throw ConfigurationError.malformedXML}
        let configurations=try decode(data,legacyCodePage:codePage,xmlTextCodePage:codePage).exportConfigurations
        guard !configurations.isEmpty else {throw ConfigurationError.invalidValue("exportConfigs")}
        return configurations
    }
    public static func decodeExportConfiguration(_ data: Data, legacyCodePage: UInt32? = nil, xmlTextCodePage: UInt32? = nil, control: ScanControl? = nil) throws -> ExportConfiguration {
        let root = try XMLTree.read(data, control: control)
        return try exportConfiguration(root, legacyCodePage: legacyCodePage, xmlTextCodePage: xmlTextCodePage)
    }
    public func encodedXML() throws -> Data {
        var builder = XMLBuilder()
        try builder.raw("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<SpaceSnifferConfig>")
        for key in Self.integerKeys + Self.booleanKeys + ["initialStyle"] { if let value = settings[key] { try builder.element(key, Self.string(value)) } }
        try builder.raw("<colors>")
        for key in Self.colorIntegerKeys + Self.colorBooleanKeys + ["levelContrast","borderContrast"] { if let value = settings["colors."+key] { try builder.element(key, Self.string(value)) } }
        try builder.raw("</colors><exportConfigs>")
        for entry in exportConfigurations { try entry.appendXML(to: &builder) }
        try builder.raw("</exportConfigs><fileGroups>")
        for group in fileClasses {
            try builder.raw("<fileGroup>")
            try builder.element("name", group.name); try builder.element("extensions", group.extensionsText); try builder.element("color", String(group.color))
            try builder.raw("</fileGroup>")
        }
        try builder.raw("</fileGroups></SpaceSnifferConfig>")
        return Data(builder.output.utf8)
    }
    private static func exportConfiguration(_ node: XMLTree.Node, legacyCodePage: UInt32?, xmlTextCodePage: UInt32?) throws -> ExportConfiguration {
        let version: Int
        if let text = node.attributes["version"] {
            version = decimalPrefix(text)
            guard (1...3).contains(version) else { throw ConfigurationError.unsupportedVersion(version) }
        } else { version = 0 } // Native ctor leaves version=0 when no attribute exists.
        func text(_ key: String) throws -> String { try nativeText(node.last(key)?.text ?? "", codePage: xmlTextCodePage) }
        func format(_ key: String) throws -> String {
            guard let value = node.last(key)?.text, !value.isEmpty else { return "" }
            guard let bytes = Data(base64Encoded: value) else { throw ConfigurationError.invalidBase64 }
            var text: String
            if version == 3 {
                guard bytes.count % 2 == 0 else { throw ConfigurationError.invalidUTF16 }
                guard let decoded = String(data: bytes, encoding: .utf16LittleEndian) else { throw ConfigurationError.invalidUTF16 }; text = decoded
            } else { text = try WindowsLegacyText.decode(bytes, codePage: legacyCodePage) }
            if version == 1 { text = text.replacingOccurrences(of: "<%size%>", with: "<%disksize%>").replacingOccurrences(of: "<%sizebytes%>", with: "<%disksizebytes%>") }
            return text
        }
        return try ExportConfiguration(description: text("description"), preferredFileName: text("preferredFileName"), preferredFileExtension: text("preferredFileExtension"),
            header: format("headerFormat"), detail: format("detailFormat"), footer: format("footerFormat"), blockSorting: text("blockSorting"), fineSorting: text("fineSorting"), direction: text("fineSortingDirection"), sourceVersion: version)
    }
    private static func nativeText(_ text: String, codePage: UInt32?) throws -> String { try WindowsLegacyText.decode(Data(text.utf8), codePage: codePage) }
    /// sortConfigs 0x40e8c0 compares adjacent nonempty descriptions by wcscmp;
    /// empty descriptions remain barriers and equal names retain input order.
    private static func sortedExports(_ source: [ExportConfiguration]) -> [ExportConfiguration] {
        var result = source, start = 0
        while start < result.count {
            if result[start].description.isEmpty { start += 1; continue }
            var end = start + 1
            while end < result.count, !result[end].description.isEmpty { end += 1 }
            let sorted = result[start..<end].enumerated().sorted {
                let a = $0.element.description.utf16, b = $1.element.description.utf16
                return a.elementsEqual(b) ? $0.offset < $1.offset : a.lexicographicallyPrecedes(b)
            }.map(\.element)
            result.replaceSubrange(start..<end, with: sorted); start = end
        }
        return result
    }
    private static func check(_ control: ScanControl?) throws { if Task.isCancelled || control?.isCancelled == true { throw CancellationError() } }
    private static func integer(_ text: String) throws -> Int32 {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines), negative = false
        if value.hasPrefix("+") || value.hasPrefix("-") { negative = value.hasPrefix("-"); value.removeFirst() }
        if value.hasPrefix("$") || value.lowercased().hasPrefix("0x") {
            value.removeFirst(value.hasPrefix("$") ? 1 : 2)
            guard let bits = UInt32(value, radix: 16) else { throw ConfigurationError.invalidValue(text) }
            if negative { guard bits <= 0x80000000 else { throw ConfigurationError.invalidValue(text) }; return bits == 0x80000000 ? .min : -Int32(bits) }
            return Int32(bitPattern: bits)
        }
        guard let signed = Int64((negative ? "-" : "") + value), signed >= Int64(Int32.min), signed <= Int64(Int32.max) else { throw ConfigurationError.invalidValue(text) }
        return Int32(signed)
    }
    private static func decimalPrefix(_ text: String) -> Int {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines); var sign = 1, result = 0, started = false
        for scalar in text.unicodeScalars {
            if !started && (scalar.value == 43 || scalar.value == 45) { sign = scalar.value == 45 ? -1 : 1; started = true; continue }
            guard (48...57).contains(scalar.value) else { break }; started = true
            let digit = Int(scalar.value - 48); guard result <= (Int.max - digit) / 10 else { return Int.max }; result = result * 10 + digit
        }
        return sign * result
    }
    private static func string(_ value: Value) -> String {
        switch value { case let .integer(value): String(value); case let .boolean(value): value ? "true" : "false"; case let .decimal(value): String(value); case let .text(value): value }
    }
    /// Counts actual UTF8 bytes, including escaping and closing tags, before
    /// creating escaped copies. This is a Mac serialization resource boundary.
    fileprivate struct XMLBuilder {
        private(set) var output = ""
        private var bytes = 0
        private let limit = 4_194_304
        mutating func raw(_ text: String) throws {
            let count = text.utf8.prefix(limit - bytes + 1).count
            guard count <= limit - bytes else { throw ConfigurationError.inputLimit }
            output += text; bytes += count
        }
        mutating func element(_ name: String, _ text: String) throws {
            try raw("<" + name + ">")
            var count = 0
            for scalar in text.unicodeScalars {
                let length: Int
                switch scalar.value {
                case 38: length = 5 // &amp;
                case 60, 62: length = 4 // &lt; &gt;
                case 0...0x7f: length = 1
                case 0...0x7ff: length = 2
                case 0...0xffff: length = 3
                default: length = 4
                }
                guard length <= limit - bytes - count else { throw ConfigurationError.inputLimit }
                count += length
            }
            output += text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            bytes += count
            try raw("</" + name + ">")
        }
    }
    private final class XMLTree: NSObject, XMLParserDelegate {
        final class Node {
            let name: String, attributes: [String: String]
            var children: [Node] = [], text = ""
            init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
            func last(_ name: String) -> Node? { children.last { $0.name == name } }
        }
        var root: Node?, stack: [Node] = [], count = 0, failed = false
        let control: ScanControl?
        init(control: ScanControl?) { self.control = control }
        static func read(_ data: Data, control: ScanControl?) throws -> Node {
            try NativeConfiguration.check(control)
            guard data.count <= 4_194_304 else { throw ConfigurationError.inputLimit }
            guard let text = String(data: data, encoding: .utf8), !text.localizedCaseInsensitiveContains("<!DOCTYPE"), !text.localizedCaseInsensitiveContains("<!ENTITY") else { throw ConfigurationError.malformedXML }
            let delegate = XMLTree(control: control), parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never; parser.delegate = delegate
            let success = parser.parse(); try NativeConfiguration.check(control)
            guard success, !delegate.failed, let root = delegate.root else { throw ConfigurationError.malformedXML }; return root
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            count += 1
            guard count <= 20_000, stack.count < 256, !Task.isCancelled, control?.isCancelled != true else { failed = true; parser.abortParsing(); return }
            let node = Node(name, attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }; stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if !stack.isEmpty { stack.removeLast() } }
        func parser(_ parser: XMLParser, foundCharacters text: String) { stack.last?.text += text }
        func parser(_ parser: XMLParser, foundCDATA data: Data) { if let text = String(data: data, encoding: .utf8) { stack.last?.text += text } else { failed = true; parser.abortParsing() } }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { failed = true; parser.abortParsing(); return nil }
    }
}
