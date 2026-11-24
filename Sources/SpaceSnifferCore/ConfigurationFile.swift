import Foundation
import Darwin
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Explicit, bounded local file import. Never applies configuration to the app.
public enum ConfigurationFile {
    public enum FileError: LocalizedError, Equatable {
        case inputLimit, invalidRoot, exportIndexRequired, invalidExportIndex, notRegularFile
        public var errorDescription: String? {
            switch self {
            case .inputLimit: return "Configuration XML exceeds the 4 MiB input limit"
            case .invalidRoot: return "Expected local SpaceSnifferConfig or exportConfig XML"
            case .exportIndexRequired: return "Full configuration requires an explicit export index from configuration inspection"
            case .invalidExportIndex: return "Export configuration index is out of range"
            case .notRegularFile: return "Configuration input must be a regular local file"
            }
        }
    }
    public struct Inspection: Sendable {
        public let configuration: NativeConfiguration?
        public let exports: [NativeConfiguration.ExportConfiguration]
        public func selectingExport(_ index: Int? = nil) throws -> NativeConfiguration.ExportConfiguration {
            if configuration != nil, index == nil { throw FileError.exportIndexRequired }
            let chosen = index ?? 0
            guard exports.indices.contains(chosen) else { throw FileError.invalidExportIndex }
            return exports[chosen]
        }
    }
    public static func inspect(_ url: URL, legacyCodePage: UInt32? = nil, xmlTextCodePage: UInt32? = nil,
                               control: ScanControl? = nil) throws -> Inspection {
        try check(control)
        guard url.isFileURL, !url.path.contains("\0") else { throw FileError.invalidRoot }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw FileError.notRegularFile }
        guard info.st_size <= 4_194_304 else { throw FileError.inputLimit }
        var data = Data()
        while true {
            try check(control)
            guard let block = try handle.read(upToCount: min(65_536, 4_194_305 - data.count)), !block.isEmpty else { break }
            data.append(block)
            guard data.count <= 4_194_304 else { throw FileError.inputLimit }
        }
        return try inspect(data, legacyCodePage: legacyCodePage, xmlTextCodePage: xmlTextCodePage, control: control)
    }
    public static func inspect(_ data: Data, legacyCodePage: UInt32? = nil, xmlTextCodePage: UInt32? = nil,
                               control: ScanControl? = nil) throws -> Inspection {
        try check(control)
        guard data.count <= 4_194_304 else { throw FileError.inputLimit }
        guard let text = String(data: data, encoding: .utf8), !text.localizedCaseInsensitiveContains("<!DOCTYPE"), !text.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw NativeConfiguration.ConfigurationError.malformedXML
        }
        // Root detection cannot expand entities. The selected codec then validates
        // the entire document, including DTD/entity preflight and resource limits.
        let parser = XMLParser(data: data), delegate = RootName()
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never
        _ = parser.parse()
        try check(control)
        switch delegate.name {
        case "SpaceSnifferConfig":
            let config = try NativeConfiguration.decode(data, legacyCodePage: legacyCodePage, xmlTextCodePage: xmlTextCodePage, control: control)
            return Inspection(configuration: config, exports: config.exportConfigurations)
        case "exportConfig":
            let config = try NativeConfiguration.decodeExportConfiguration(data, legacyCodePage: legacyCodePage, xmlTextCodePage: xmlTextCodePage, control: control)
            return Inspection(configuration: nil, exports: [config])
        default: throw FileError.invalidRoot
        }
    }
    private static func check(_ control: ScanControl?) throws { if Task.isCancelled || control?.isCancelled == true { throw CancellationError() } }
    private final class RootName: NSObject, XMLParserDelegate {
        var name: String?
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            name = elementName; parser.abortParsing()
        }
    }
}
