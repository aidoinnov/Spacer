import Foundation
import SpaceSnifferCore

/// CLI-only option validation and JSON presentation; no application state changes.
enum HeadlessConfiguration {
    enum OptionError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(text) = self { return text }; return nil }
    }
    struct Request {
        let inspect: String?, export: String?, index: Int?, legacyCodePage: UInt32?, xmlTextCodePage: UInt32?, maximumOutputBytes: Int64
        func read(_ path: String) throws -> ConfigurationFile.Inspection {
            try ConfigurationFile.inspect(URL(fileURLWithPath: path), legacyCodePage: legacyCodePage, xmlTextCodePage: xmlTextCodePage)
        }
    }
    static func parse(_ args: [String]) throws -> Request {
        func value(_ flag: String) throws -> String? {
            guard let index = args.firstIndex(of: flag) else { return nil }
            guard args.indices.contains(index + 1), !args[index + 1].hasPrefix("--"), args.filter({ $0 == flag }).count == 1 else {
                throw OptionError.invalid("Expected one value for \(flag)")
            }
            return args[index + 1]
        }
        func page(_ flag: String) throws -> UInt32? {
            guard let text = try value(flag) else { return nil }
            guard let result = UInt32(text), (1...65535).contains(result) else { throw OptionError.invalid("Invalid Windows code page: \(flag)") }
            return result
        }
        let inspect = try value("--inspect-config"), export = try value("--export-config")
        guard inspect == nil || export == nil else { throw OptionError.invalid("Choose --inspect-config or --export-config") }
        var index: Int?
        if let text = try value("--export-config-index") {
            guard let value = Int(text), value >= 0, export != nil else { throw OptionError.invalid("--export-config-index requires --export-config and a nonnegative integer") }; index = value
        }
        var budget: Int64 = 1_073_741_824
        if let text = try value("--max-output-bytes") {
            guard let value = Int64(text), value >= 0, export != nil else { throw OptionError.invalid("--max-output-bytes requires --export-config and a nonnegative integer") }; budget = value
        }
        let legacy = try page("--config-legacy-code-page"), xml = try page("--config-xml-code-page")
        guard inspect != nil || export != nil || (legacy == nil && xml == nil) else { throw OptionError.invalid("Configuration code pages require --inspect-config or --export-config") }
        if export != nil {
            guard let path = try value("--output"), URL(fileURLWithPath: path).pathExtension.lowercased() == "txt" else {
                throw OptionError.invalid("--export-config requires --output FILE.txt")
            }
        }
        return Request(inspect: inspect, export: export, index: index, legacyCodePage: legacy, xmlTextCodePage: xml, maximumOutputBytes: budget)
    }
    static func inspectionJSON(_ source: ConfigurationFile.Inspection) throws -> Data {
        var result: [String: Any] = ["document_kind": source.configuration == nil ? "exportConfig" : "SpaceSnifferConfig",
            "requires_export_index": source.configuration != nil,
            "exports": source.exports.enumerated().map { index, value -> [String: Any] in
                ["export_index": index, "description": value.description, "source_version": value.sourceVersion,
                 "preferred_file_name": value.preferredFileName, "preferred_file_extension": value.preferredFileExtension,
                 "header": value.headerFormat, "detail": value.detailFormat, "footer": value.footerFormat,
                 "block_sorting": value.blockSorting, "fine_sorting": value.fineSorting, "direction": value.fineSortingDirection]
            }]
        if let config = source.configuration {
            result["settings"] = config.settings.mapValues { value -> Any in
                switch value { case let .integer(v): return v; case let .boolean(v): return v; case let .decimal(v): return v; case let .text(v): return v }
            }
            result["file_classes"] = config.fileClasses.map { ["name": $0.name, "extensions_text": $0.extensionsText, "extensions": $0.extensions, "native_color": $0.color] as [String: Any] }
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }
}
