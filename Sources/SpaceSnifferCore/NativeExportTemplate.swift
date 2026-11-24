import Foundation

/// Reconstructed text atoms: atomizeFormat 0x418fe0, recurse 0x419480,
/// buildExportRow 0x416e60, resolveTags 0x419aa0. Never executes host code.
public struct NativeExportTemplate: Sendable {
    public enum TemplateError: Error, Equatable { case inputLimit, nestingLimit, atomLimit, outputLimit, workLimit, unclosedGroup, invalidNesting, unsupportedNumber }
    public struct Limits: Sendable {
        public let inputUTF16: Int, nesting: Int, atoms: Int, outputUTF16: Int, workUTF16: Int
        public init(inputUTF16: Int = 1_048_576, nesting: Int = 128, atoms: Int = 65_536, outputUTF16: Int = 8_388_608, workUTF16: Int = 33_554_432) {
            self.inputUTF16 = max(1, min(inputUTF16, 1_048_576)); self.nesting = max(1, min(nesting, 128))
            self.atoms = max(1, min(atoms, 65_536)); self.outputUTF16 = max(1, min(outputUTF16, 8_388_608))
            self.workUTF16 = max(1, min(workUTF16, 33_554_432))
        }
    }
    public enum LineBreaks: Sendable, Equatable { case preview, fileText }
    private indirect enum Atom: Sendable { case literal(String), group([Atom]) }
    private let root: Atom
    private let limits: Limits
    public let source: String
    public let referencedTags: Set<String>
    public static let knownTags: Set<String> = ["file", "filename", "fileext", "path", "pathfile", "size", "sizebytes", "disksize", "disksizebytes",
        "filecreatedate", "filecreatetime", "filecreateage", "filemodifydate", "filemodifytime", "filemodifyage", "fileaccessdate", "fileaccesstime", "fileaccessage",
        "isfile", "isfolder", "iscontainer", "containsfiles", "containsfolders", "containscontainers", "nestinglevel", "count", "localcount", "filecount", "localfilecount", "foldercount", "localfoldercount", "containercount", "localcontainercount"]
    public init(_ source: String, limits: Limits = Limits(), control: ScanControl? = nil) throws {
        guard source.utf16.count <= limits.inputUTF16 else { throw TemplateError.inputLimit }
        self.source = source; self.limits = limits
        var text = source
        let trimmed = Self.trimLeft(text)
        if trimmed.hasPrefix("{script}") {
            text = String(trimmed.dropFirst(8)).replacingOccurrences(of: "\r\n", with: "").replacingOccurrences(of: "\t", with: "")
        }
        var parser = Parser(units: Array(text.utf16), limits: limits, control: control)
        root = try parser.parse(0..<parser.units.count, depth: 0) ?? .literal("")
        referencedTags = parser.tags
    }
    /// Values are supplied by a frozen row context. Relative clocks/OS formatters
    /// belong to that context, never to parser/cache global state.
    public func render(values: [String: String], nestingLevel: Int = 0, lineBreaks: LineBreaks = .fileText,
                       decimalSeparator: Character = ".", control: ScanControl? = nil) throws -> String {
        guard nestingLevel >= 0 else { throw TemplateError.invalidNesting }
        var evaluation = Evaluation(values: values, nestingLevel: nestingLevel, lineBreaks: lineBreaks, decimalSeparator: decimalSeparator, limits: limits, control: control)
        return try evaluation.evaluate(root)
    }
    private static func check(_ control: ScanControl?) throws {
        if Task.isCancelled || control?.isCancelled == true { throw CancellationError() }
    }
    private static func trim(_ s: String) -> String { String(decoding: s.utf16.drop(while: { $0 <= 32 }).reversed().drop(while: { $0 <= 32 }).reversed(), as: UTF16.self) }
    private static func trimLeft(_ s: String) -> String { String(decoding: s.utf16.drop(while: { $0 <= 32 }), as: UTF16.self) }
    private static func tokens(_ text: String) -> [(Range<String.Index>, String)] {
        var result: [(Range<String.Index>, String)] = [], tail = text.startIndex
        while tail < text.endIndex {
            let remainder = text[tail...]
            guard let open = remainder.range(of: "<%"), let close = remainder.range(of: "%>"), open.lowerBound < close.lowerBound else { break }
            result.append((open.lowerBound..<close.upperBound, String(text[open.upperBound..<close.lowerBound])))
            tail = close.upperBound
        }
        return result
    }
    private struct Parser {
        let units: [UInt16], limits: Limits, control: ScanControl?
        var atoms = 0, work = 0; var tags: Set<String> = []
        mutating func spend() throws {
            work += 1
            if work % 128 == 0 { try NativeExportTemplate.check(control) }
            guard work <= limits.workUTF16 else { throw TemplateError.workLimit }
        }
        mutating func atom(_ atom: Atom) throws -> Atom {
            atoms += 1; guard atoms <= limits.atoms else { throw TemplateError.atomLimit }; return atom
        }
        mutating func literal(_ range: Range<Int>) throws -> Atom {
            let text = String(decoding: units[range], as: UTF16.self)
            for (_, tag) in NativeExportTemplate.tokens(text) { tags.insert(tag) }
            return try atom(.literal(text))
        }
        mutating func parse(_ range: Range<Int>, depth: Int) throws -> Atom? {
            try NativeExportTemplate.check(control)
            guard depth <= limits.nesting else { throw TemplateError.nestingLimit }
            guard !range.isEmpty else { return nil }
            var cursor = range.lowerBound, children: [Atom] = []
            while cursor < range.upperBound {
                var open = cursor
                while open < range.upperBound, units[open] != 123 { try spend(); open += 1 }
                if open == range.upperBound { children.append(try literal(cursor..<open)); break }
                if open > cursor { children.append(try literal(cursor..<open)) }
                var end = open + 1, nested = 0
                while end < range.upperBound {
                    try spend()
                    if units[end] == 123 { nested += 1 }
                    else if units[end] == 125 { if nested == 0 { break }; nested -= 1 }
                    end += 1
                }
                guard end < range.upperBound else { throw TemplateError.unclosedGroup }
                if let child = try parse((open + 1)..<end, depth: depth + 1) { children.append(child) }
                cursor = end + 1
                // Native recurse discards a suffix only when it is entirely whitespace.
                var tail = cursor
                while tail < range.upperBound, units[tail] <= 32 { try spend(); tail += 1 }
                if tail == range.upperBound { cursor = tail }
            }
            return try atom(.group(children))
        }
    }
    private struct Evaluation {
        let values: [String: String], nestingLevel: Int, lineBreaks: LineBreaks, decimalSeparator: Character, limits: Limits, control: ScanControl?
        var work = 0
        mutating func charge(_ text: String) throws -> String {
            try NativeExportTemplate.check(control)
            let count = text.utf16.count
            guard count <= limits.outputUTF16 else { throw TemplateError.outputLimit }
            guard count <= limits.workUTF16 - work else { throw TemplateError.workLimit }
            work += count; return text
        }
        mutating func resolve(_ text: String) throws -> String {
            var result = "", tail = text.startIndex, units = 0
            func checkedAppend(_ part: String) throws {
                let count = part.utf16.count
                guard count <= limits.outputUTF16 - units else { throw TemplateError.outputLimit }
                units += count; result += part
            }
            for (range, tag) in NativeExportTemplate.tokens(text) {
                try NativeExportTemplate.check(control)
                try checkedAppend(String(text[tail..<range.lowerBound]))
                if tag == "nestinglevel" { try checkedAppend(String(nestingLevel)) }
                else if !NativeExportTemplate.knownTags.contains(tag) { try checkedAppend("*BAD TAG*") }
                else if let value = values[tag] { try checkedAppend(value) }
                else if tag.hasSuffix("count") || tag.hasSuffix("bytes") { try checkedAppend("0") }
                else if tag.hasPrefix("is") || tag.hasPrefix("contains") { try checkedAppend("false") }
                else { try checkedAppend("*VOID*") }
                tail = range.upperBound
            }
            try checkedAppend(String(text[tail...])); return try charge(result)
        }
        mutating func evaluate(_ atom: Atom) throws -> String {
            try NativeExportTemplate.check(control)
            let parts: [String]
            switch atom {
            case let .literal(text): parts = [try resolve(text)]
            case let .group(children): parts = try children.map { try evaluate($0) }
            }
            if parts.isEmpty { return "" }
            if parts.count == 1 {
                switch NativeExportTemplate.trim(parts[0]) {
                case "&br": return try charge(lineBreaks == .fileText ? "\n" : "\r\n")
                case "&tab": return try charge("\t")
                case "&curlyop": return try charge("{")
                case "&curlycl": return try charge("}")
                case "&angleop": return try charge("<")
                case "&anglecl": return try charge(">")
                default: break
                }
            }
            let command = NativeExportTemplate.trim(parts[0])
            if parts.count == 2, command == "nest" {
                let count = parts[1].utf16.count
                if count == 0 { return "" }
                guard count == 0 || nestingLevel <= limits.outputUTF16 / count else { throw TemplateError.outputLimit }
                return try charge(String(repeating: parts[1], count: nestingLevel))
            }
            if parts.count == 4, command == "leftpad" || command == "rightpad" {
                let target = Self.decimalPrefix(parts[3])
                guard target >= 0, target <= limits.outputUTF16 else { throw TemplateError.outputLimit }
                var text = Array(parts[1].utf16)
                let pad = Array((parts[2].isEmpty ? "*BAD PAD*" : parts[2]).utf16)
                if target > text.count {
                    let repetitions = (target - text.count + pad.count - 1) / pad.count
                    var padding: [UInt16] = []; padding.reserveCapacity(repetitions * pad.count)
                    for i in 0..<repetitions { if i % 128 == 0 { try NativeExportTemplate.check(control) }; padding.append(contentsOf: pad) }
                    text = command == "leftpad" ? padding + text : text + padding
                }
                return try charge(String(decoding: command == "leftpad" ? Array(text.suffix(target)) : Array(text.prefix(target)), as: UTF16.self))
            }
            if (parts.count == 6 || parts.count == 8), command == "if", NativeExportTemplate.trim(parts[4]) == "?",
               parts.count == 6 || NativeExportTemplate.trim(parts[6]) == ":" {
                let lhs = parts[1], rhs = parts[3], op = NativeExportTemplate.trim(parts[2])
                let same = lhs.utf16.elementsEqual(rhs.utf16)
                let comparison: Int
                if ["<", "<=", ">", ">="].contains(op), let a = try number(lhs), let b = try number(rhs) { comparison = a < b ? -1 : a > b ? 1 : 0 }
                else { comparison = same ? 0 : lhs.utf16.lexicographicallyPrecedes(rhs.utf16) ? -1 : 1 }
                let condition: Bool?
                switch op { case "==": condition = same; case "!=": condition = !same; case "<": condition = comparison < 0
                case "<=": condition = comparison <= 0; case ">": condition = comparison > 0; case ">=": condition = comparison >= 0; default: condition = nil }
                if let condition { return try charge(condition ? parts[5] : parts.count == 8 ? parts[7] : "") }
            }
            // This is the observed buildExportRow fallback, not an invented command.
            // Literal groups and unrecognized atom sequences concatenate their results.
            var result = "", units = 0
            for part in parts {
                let count = part.utf16.count
                guard count <= limits.outputUTF16 - units else { throw TemplateError.outputLimit }
                units += count; result += part
            }
            return try charge(result)
        }
        private func number(_ text: String) throws -> Double? {
            let trimmed = NativeExportTemplate.trim(text)
            if decimalSeparator != ".", trimmed.contains(".") { return nil }
            let value = Double(decimalSeparator == "." ? trimmed : trimmed.replacingOccurrences(of: String(decimalSeparator), with: "."))
            if let value, !value.isFinite { throw TemplateError.unsupportedNumber }
            return value
        }
        private static func decimalPrefix(_ text: String) -> Int {
            let units = Array(NativeExportTemplate.trimLeft(text).utf16); var index = 0, negative = false, value = 0
            if units.first == 43 || units.first == 45 { negative = units.first == 45; index += 1 }
            while index < units.count, units[index] >= 48, units[index] <= 57 {
                let digit = Int(units[index] - 48)
                if value > (Int(Int32.max) - digit) / 10 { return Int.max }
                value = value * 10 + digit; index += 1
            }
            return negative ? -value : value
        }
    }
}
