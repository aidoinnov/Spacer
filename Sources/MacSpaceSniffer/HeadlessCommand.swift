import Foundation
import SpaceSnifferCore

/// Uses the same scanner and filter as the app, without starting an AppKit window.
enum HeadlessCommand {
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.contains("--cli") || args.contains("--help") else { return }
        if args.contains("--help") {
            print("""
            Mac Space Sniffer
              --scan PATH                       Open the app and scan a folder
              --snapshot FILE                   Open a SNS or supported DU snapshot in the app
              --cli --scan PATH [options]        Scan without a window
              --cli --load FILE [options]        Read a saved snapshot
            Options:
              --output FILE.txt|FILE.sns        Export a report or complete snapshot
              --filter '*.zip;>100mb'            Filter exported file list
              --logical                         Use logical size for filtering view weights
              --hide-hidden                     Omit hidden paths from exported file list
              --legacy-code-page NUMBER         Original Windows ANSI code page for SNS v2/DU
              --snapshot-root-index NUMBER      Select a top-level snapshot root (zero-based)
              --list-roots                      With --load: list all roots without selecting one
              --issues                          Include stored scan issues in summary JSON
              --include-mounted-volumes         Include nested mounted volumes (default: selected volume only)
              --cli --inspect-config FILE       Inspect native config/export XML as JSON; no scan
              --export-config FILE              Use explicit native XML template for TXT output
              --export-config-index NUMBER      Required for a full config; index from inspection
              --config-legacy-code-page NUMBER  Original ANSI page for legacy template Base64
              --config-xml-code-page NUMBER     Original runtime page for non-ASCII XML text
              --max-output-bytes NUMBER         Configured report byte cap (default 1073741824)
            SNS saves the current filtered tree in the native binary format. TXT uses the original Simple file list preset.
            Configured exports use Mac localized dates/times/relative ages; explicit XML never overwrites app settings.
            """)
            exit(0)
        }
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        do {
            let configRequest = try HeadlessConfiguration.parse(args)
            if let path = configRequest.inspect {
                let data = try HeadlessConfiguration.inspectionJSON(configRequest.read(path))
                print(String(decoding: data, as: UTF8.self)); exit(0)
            }
            // Validate the explicit template selection before scanning/loading.
            let exportConfig = try configRequest.export.map { try configRequest.read($0).selectingExport(configRequest.index) }
            let snapshot: ScanSnapshot
            if let path = value("--scan") {
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { throw CLIError.message("Not a directory: \(path)") }
                snapshot = DiskScanner.scan(URL(fileURLWithPath: path), volumeTraversal: args.contains("--include-mounted-volumes") ? .allVolumes : .selectedVolume)
            } else if let path = value("--load") {
                let url = URL(fileURLWithPath: path)
                var codePage: UInt32?
                if let raw = value("--legacy-code-page") {
                    guard let page = UInt32(raw), (1...65535).contains(page) else { throw CLIError.message("Invalid Windows code page") }
                    codePage = page
                }
                if args.contains("--list-roots") {
                    let roots = try ArtifactTransfer.inspectRoots(url, legacyCodePage: codePage)
                    let rows: [[String: Any]] = roots.map { root in
                        ["root_index": root.index, "path": root.path, "files": root.files, "folders": root.folders,
                         "logical_bytes": root.logicalBytes, "allocated_bytes": root.allocatedBytes]
                    }
                    let result = try JSONSerialization.data(withJSONObject: ["roots": rows], options: [.sortedKeys])
                    print(String(decoding: result, as: UTF8.self)); exit(0)
                }
                var rootIndex: Int?
                if let raw = value("--snapshot-root-index") {
                    guard let index = Int(raw), index >= 0 else { throw CLIError.message("Invalid snapshot root index") }
                    rootIndex = index
                }
                snapshot = try ArtifactTransfer.load(url, legacyCodePage: codePage, rootIndex: rootIndex)
            } else { throw CLIError.message("Expected --scan PATH or --load FILE") }
            guard !snapshot.nodes.isEmpty else { throw CLIError.message(snapshot.issues.joined(separator: "\n")) }
            let filter = try ScanFilter(value("--filter") ?? "")
            let mode: SizeMode = args.contains("--logical") ? .logical : .allocated
            let now = Date()
            // Configured traversal owns its membership/weights while writing;
            // delay CLI-only summary projection to avoid retaining both copies.
            let projection = exportConfig == nil ? ArtifactProjection(snapshot, filter: filter, mode: mode, showHidden: !args.contains("--hide-hidden"), now: now) : nil
            if let output = value("--output") {
                let url = URL(fileURLWithPath: output)
                if url.pathExtension.lowercased() == "sns" {
                    try ArtifactTransfer.save(projection!, to: url)
                } else if url.pathExtension.lowercased() == "txt" {
                    if let exportConfig {
                        let options = ConfiguredExportOptions(configuration: exportConfig, filter: filter, mode: mode,
                            showHidden: !args.contains("--hide-hidden"), formatting: MacExportFormatting.localized(),
                            now: now, maximumOutputBytes: configRequest.maximumOutputBytes)
                        try ArtifactTransfer.exportConfigured(snapshot, options: options, to: url)
                    } else { try ArtifactTransfer.export(projection!, to: url) }
                } else { throw CLIError.message("Output extension must be .txt or .sns") }
            }
            let matchedBytes = projection?.matchedBytes ?? ArtifactProjection(snapshot, filter: filter, mode: mode, showHidden: !args.contains("--hide-hidden"), now: now).matchedBytes
            var summary: [String: Any] = ["root": snapshot.rootPath, "files": snapshot.fileCount,
                "folders": snapshot.folderCount, "logicalBytes": snapshot.nodes[0].logicalBytes,
                "allocatedBytes": snapshot.nodes[0].allocatedBytes, "matchedBytes": matchedBytes,
                "issues": snapshot.issueCount, "cancelled": snapshot.cancelled]
            if args.contains("--issues") { summary["issue_details"] = snapshot.issues; summary["stored_issues"] = snapshot.issues.count }
            if let coverage = snapshot.volumeCoverage {
                summary["volume_traversal"] = coverage.traversal.rawValue
                summary["excluded_boundary_count"] = coverage.excludedCount
                summary["excluded_boundaries"] = coverage.exclusions.map { ["path": $0.path, "reason": $0.reason] }
            }
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(snapshot.issueCount > 0 ? 2 : 0)
        } catch {
            FileHandle.standardError.write(Data("MacSpaceSniffer: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
private enum CLIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
