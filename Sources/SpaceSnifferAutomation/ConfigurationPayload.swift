import SpaceSnifferCore

public enum ConfigurationPayload {
    public static func inspection(_ value: ConfigurationFile.Inspection, selectedIndex: Int? = nil) throws -> JSONValue {
        let selected = try selectedIndex.map { try value.selectingExport($0) }
        return .object([
            "applied_to_window": .bool(false),
            "kind": .string(value.configuration == nil ? "exportConfig" : "SpaceSnifferConfig"),
            "export_index_required": .bool(value.configuration != nil),
            "settings_keys": .array((value.configuration?.settings.keys.sorted() ?? []).map(JSONValue.string)),
            "settings": .object((value.configuration?.settings ?? [:]).mapValues { setting in
                switch setting {
                case let .integer(value): .integer(Int64(value))
                case let .boolean(value): .bool(value)
                case let .decimal(value): .number(value)
                case let .text(value): .string(value)
                }
            }),
            "selected_export": selected.map { configuration in .object([
                "header": .string(configuration.headerFormat), "detail": .string(configuration.detailFormat),
                "footer": .string(configuration.footerFormat)]) } ?? .null,
            "file_classes": .array((value.configuration?.fileClasses ?? []).map { group in
                .object(["name": .string(group.name), "extensions_text": .string(group.extensionsText), "extensions": .array(group.extensions.map(JSONValue.string)), "windows_color": .integer(Int64(group.color))])
            }),
            "exports": .array(value.exports.enumerated().map { index, configuration in
                .object(["index": .int(index), "description": .string(configuration.description),
                    "source_version": .int(configuration.sourceVersion), "preferred_file_name": .string(configuration.preferredFileName),
                    "preferred_file_extension": .string(configuration.preferredFileExtension),
                    "block_sorting": .string(configuration.blockSorting), "fine_sorting": .string(configuration.fineSorting),
                    "direction": .string(configuration.fineSortingDirection),
                    "template_utf8_bytes": .int(configuration.headerFormat.utf8.count + configuration.detailFormat.utf8.count + configuration.footerFormat.utf8.count)])
            })
        ])
    }
}
