import Foundation

/// Strict CLI boundary. Native configuration parsing owns template semantics.
struct HeadlessArguments {
    enum Invalid: LocalizedError {
        case option(String)
        var errorDescription: String? {
            if case let .option(message) = self { return message }; return nil
        }
    }
    private(set) var values: [String: String] = [:]
    private(set) var switches: Set<String> = []
    init(_ args: [String]) throws {
        let flags: Set<String> = ["--cli", "--help", "--logical", "--hide-hidden", "--list-roots", "--issues", "--include-mounted-volumes"]
        let options: Set<String> = ["--scan", "--load", "--output", "--filter", "--legacy-code-page", "--snapshot-root-index",
            "--inspect-config", "--export-config", "--export-config-index", "--config-legacy-code-page", "--config-xml-code-page", "--max-output-bytes"]
        var index = 0
        while index < args.count {
            let key = args[index]
            guard values[key] == nil && !switches.contains(key) else { throw Invalid.option("Repeated option: \(key)") }
            if flags.contains(key) { switches.insert(key) }
            else if options.contains(key) {
                guard args.indices.contains(index + 1), !args[index + 1].hasPrefix("--") else {
                    throw Invalid.option("Expected a value for \(key)")
                }
                index += 1; values[key] = args[index]
            } else { throw Invalid.option("Unknown option: \(key)") }
            index += 1
        }
        guard ["--scan", "--load", "--inspect-config"].filter({ values[$0] != nil }).count == 1 else {
            throw Invalid.option("Choose exactly one of --scan PATH, --load FILE, or --inspect-config FILE")
        }
        for key in ["--legacy-code-page", "--snapshot-root-index", "--list-roots"] {
            if values[key] != nil || switches.contains(key) {
                guard values["--load"] != nil else { throw Invalid.option("\(key) requires --load") }
            }
        }
        if switches.contains("--list-roots"), values["--output"] != nil || values["--snapshot-root-index"] != nil {
            throw Invalid.option("--list-roots cannot be combined with --output or --snapshot-root-index")
        }
        if values["--inspect-config"] != nil {
            let allowed: Set<String> = ["--inspect-config", "--config-legacy-code-page", "--config-xml-code-page"]
            guard Set(values.keys).isSubset(of: allowed), switches.isSubset(of: ["--cli"]) else {
                throw Invalid.option("--inspect-config cannot be combined with scan/export options")
            }
        }
    }
    func value(_ flag: String) -> String? { values[flag] }
}
