import Foundation

/// Reference contracts: TFilterEngine ctor 0x43f450, isIncluded 0x444870,
/// patternMatch_internal 0x445050, isMinMaxSize 0x43fd20, isMinMaxAge 0x440810.
public struct ScanFilter: Sendable {
    public let text: String
    public let isEmpty: Bool
    public var isTagDependent: Bool { includeTags != 0 || excludeTags != 0 }
    var needsAncestorContext: Bool { isTagDependent || !folderIncludes.isEmpty || !folderExcludes.isEmpty }
    /// Relative-age conditions must be reevaluated even when all snapshot inputs are unchanged.
    public var isTimeDependent: Bool {
        bounds.contains { metric, _ in
            switch metric { case .created, .accessed, .modified: true; default: false }
        }
    }
    private struct Mask: @unchecked Sendable {
        let regex: NSRegularExpression
        let asciiLiteral: [UInt8]?
        let suffix: Bool
        private static func folded(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte + 32 : byte }
        init(_ value: String) throws {
            let pattern = "\\A" + NSRegularExpression.escapedPattern(for: value)
                .replacingOccurrences(of: "\\*", with: "[\\s\\S]*").replacingOccurrences(of: "\\?", with: "[\\s\\S]") + "\\z"
            // Native matches 0x445370 treats LF/CR as ordinary non-NUL bytes
            // and requires the real end, not ICU '$' before a final newline.
            // A character class also keeps CR and LF separate (ICU dotAll can
            // consume their sequence as one match).
            regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            suffix = value.hasPrefix("*")
            let literal = suffix ? String(value.dropFirst()) : value
            asciiLiteral = !literal.contains("*") && !literal.contains("?") && literal.utf8.allSatisfy { $0 >= 32 && $0 < 127 }
                ? Array(literal.utf8) : nil
        }
        func matches(_ name: String) -> Bool {
            // ICU remains the fallback for Unicode, line endings and complex
            // masks. ASCII literals/extensions need no NSString/regex bridge.
            if let literal = asciiLiteral, name.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) {
                let bytes = name.utf8
                guard suffix ? bytes.count >= literal.count : bytes.count == literal.count else { return false }
                return bytes.suffix(literal.count).elementsEqual(literal, by: { (lhs: UInt8, rhs: UInt8) -> Bool in
                    Self.folded(lhs) == Self.folded(rhs)
                })
            }
            return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
    }
    private var fileIncludes: [Mask] = [], fileExcludes: [Mask] = []
    private var folderIncludes: [Mask] = [], folderExcludes: [Mask] = []
    private var includeTags = 0, excludeTags = 0
    private var includeAttrs: UInt32 = 0, excludeAttrs: UInt32 = 0
    private var includeADS = false, excludeADS = false
    private enum Metric: Hashable, Sendable { case logical, allocated, created, accessed, modified }
    private struct Bounds: Sendable { var minimum: Int64?; var maximum: Int64? }
    private var bounds: [(Metric, Bounds)] = []

    public init(_ text: String) throws {
        self.text = text
        // 0x43f450 discards trimmed empty ';' segments. A separator-only input
        // must use the same empty-filter path, including empty directories.
        self.isEmpty = text.split(separator: ";", omittingEmptySubsequences: true).allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var parsedBounds: [Metric: Bounds] = [:]
        // ';' is the only outer delimiter. File masks OR together; excludes AND together.
        for raw in text.split(separator: ";", omittingEmptySubsequences: true) {
            var token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else { continue }
            let excluded = token.hasPrefix("|")
            if excluded { token.removeFirst() }
            if token.hasPrefix(":tag:") || token.hasPrefix(":tags:") {
                let payload = String(token.dropFirst(token.hasPrefix(":tags:") ? 6 : 5))
                for (value, negative) in Self.tokens(payload) {
                    guard let mask = Self.tagMask(value) else { throw FilterError.invalid(String(raw)) }
                    if excluded != negative { excludeTags |= mask } else { includeTags |= mask }
                }
            } else if token.hasPrefix(":"), let mask = Self.tagMask(String(token.dropFirst())) {
                if excluded { excludeTags |= mask } else { includeTags |= mask }
            } else if token.hasPrefix(":attr:") || token.hasPrefix(":attrs:") {
                let payload = String(token.dropFirst(token.hasPrefix(":attrs:") ? 7 : 6))
                for (value, negative) in Self.tokens(payload) {
                    if ["alternatedatastream", "alternate", "altern", "alt", "ads"].contains(value) {
                        if excluded != negative { excludeADS = true } else { includeADS = true }
                    } else {
                        guard let mask = Self.attributeMask(value) else { throw FilterError.invalid(String(raw)) }
                        if excluded != negative { excludeAttrs |= mask } else { includeAttrs |= mask }
                    }
                }
            } else if token.hasPrefix(":class:") {
                let name = String(token.dropFirst(7))
                guard let extensions = Self.fileClasses[name] else { throw FilterError.invalid(String(raw)) }
                for ext in extensions.split(separator: ";") {
                    if excluded { fileExcludes.append(try Mask("*." + ext)) }
                    else { fileIncludes.append(try Mask("*." + ext)) }
                }
            } else if token.hasPrefix("\\") {
                let mask = try Mask(String(token.dropFirst()))
                if excluded { folderExcludes.append(mask) } else { folderIncludes.append(mask) }
            } else if !excluded, let op = token.firstIndex(where: { $0 == ">" || $0 == "<" }) {
                let field = token[..<op].trimmingCharacters(in: .whitespaces)
                let value = token[token.index(after: op)...].trimmingCharacters(in: .whitespaces)
                let digits = value.prefix(while: { $0.isASCII && $0.isNumber })
                let unit = value.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
                guard !digits.isEmpty, let number = Int64(digits) else { throw FilterError.invalid(String(raw)) }
                let metric: Metric; let multiplier: Int64
                let sizeUnits: [String: Int64] = ["b": 1, "kb": 1024, "mb": 1048576, "gb": 1073741824, "tb": 1099511627776]
                if let scale = sizeUnits[unit], field.isEmpty || Self.matchesAny(field, ["disksize", "clustersize", "filesize", "logicalsize", "size"]) {
                    metric = field.isEmpty || Self.matchesAny(field, ["disksize", "clustersize"]) ? .allocated : .logical
                    multiplier = scale
                } else if let scale = Self.ageUnits[unit], field.isEmpty || Self.matchesAny(field, ["create", "creation", "accessed", "modify", "modified", "modification"]) {
                    metric = Self.matchesAny(field, ["create", "creation"]) ? .created : Self.matchesAny(field, ["accessed"]) ? .accessed : .modified
                    multiplier = scale
                } else { throw FilterError.invalid(String(raw)) }
                let result = number.multipliedReportingOverflow(by: multiplier)
                guard !result.overflow else { throw FilterError.invalid(String(raw)) }
                var range = parsedBounds[metric] ?? Bounds()
                // The native constructor consumes tokens in reverse: first bound for each direction wins.
                if token[op] == ">" { if range.minimum == nil { range.minimum = result.partialValue } }
                else { if range.maximum == nil { range.maximum = result.partialValue } }
                parsedBounds[metric] = range
            } else {
                let mask = try Mask(token)
                if excluded { fileExcludes.append(mask) } else { fileIncludes.append(mask) }
            }
        }
        bounds = parsedBounds.compactMap { metric, original in
            var range = original
            switch metric {
            case .created, .accessed, .modified:
                // Native age fields use 0 (not -1 like size fields) as the
                // disabled sentinel, including an explicitly parsed <0s/>0s.
                if range.minimum == 0 { range.minimum = nil }
                if range.maximum == 0 { range.maximum = nil }
            default: break
            }
            return range.minimum == nil && range.maximum == nil ? nil : (metric, range)
        }
    }
    private static func matchesAny(_ value: String, _ candidates: [String]) -> Bool {
        guard !value.isEmpty else { return false }
        return candidates.contains { candidate in
            guard value.first == candidate.first else { return false }
            var cursor = candidate.startIndex
            for char in value {
                guard let match = candidate[cursor...].firstIndex(of: char) else { return false }
                cursor = candidate.index(after: match)
            }
            return true
        }
    }
    // Native tokenize 0x445bd0: ',' resets sign; '+'/'-' set sign for the following token.
    private static func tokens(_ text: String) -> [(String, Bool)] {
        var result: [(String, Bool)] = []; var part = ""; var negative = false
        for char in text {
            if char == "," || char == "+" || char == "-" {
                let value = part.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { result.append((value, negative)) }
                part = ""; negative = char == "-"
            } else { part.append(char) }
        }
        let value = part.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty { result.append((value, negative)) }
        return result
    }
    private static func tagMask(_ value: String) -> Int? {
        // Byte strings 0x740d80 and examineTagToken 0x4455b0: 3=green, 4=blue.
        ["1": 1, "r": 1, "red": 1, "2": 2, "y": 2, "yellow": 2,
         "3": 4, "g": 4, "green": 4, "4": 8, "b": 8, "blu": 8, "blue": 8,
         "a": 15, "all": 15][value]
    }
    private static func attributeMask(_ value: String) -> UInt32? {
        let groups: [(String, UInt32)] = [("archive,archi,arch,arc,ar,a", 0x20), ("system,sys,s", 4),
            ("readonly,rdonly,ronly,rdo,ro,r", 1), ("hidden,hidn,hid,h", 2),
            ("compressed,comprsd,compr,cpr,c", 0x800), ("encrypted,encrptd,encptd,enc,e,crypted,crypt,cptd", 0x4000),
            ("offline,off,ol,o", 0x1000), ("temporary,temp,tmp,t", 0x100),
            ("notindexed,notindx,notidx,noidx,nidx,ni", 0x2000), ("sparse,sp", 0x200)]
        return groups.first { $0.0.split(separator: ",").contains(Substring(value)) }?.1
    }
    private static let ageUnits: [String: Int64] = ["seconds": 1, "secs": 1, "sec": 1, "s": 1,
        "minutes": 60, "mins": 60, "min": 60, "m": 60, "hours": 3600, "hour": 3600, "h": 3600,
        "days": 86400, "day": 86400, "d": 86400, "weeks": 604800, "week": 604800, "w": 604800,
        "months": 2592000, "month": 2592000, "years": 31536000, "year": 31536000, "y": 31536000]
    // Default file classes observed in getConfig 0x40c420 and literals at 0x73d5ec onward.
    private static let fileClasses = [
        "video/movies": "qt;mov;mpeg;mpg;mpe;m1s;mp4;avi;mts;vob;wmv;rm;3gp;mkv",
        "executables/system files": "exe;dll;sys;ini;msi;log", "archives/disk images": "zip;7z;rar;iso",
        "pictures/images": "jpg;jpeg;gif;png;tif;tiff;nef;raw;rw2;cr2;bmp;psd",
        "audio/music": "mp2;mp3;wav;ogg;aif;alp;au;3gp;ac3;amr;aac;m4a;wma;aiff;flac;m4a;voc"]
    public func matches(_ node: DiskNode, snapshot: ScanSnapshot, now: Date = Date(), inheritedTagMask: Int? = nil) -> Bool {
        evaluate(node, snapshot: snapshot, now: now, inheritedTagMask: inheritedTagMask, folderState: nil)
    }
    private func evaluate(_ node: DiskNode, snapshot: ScanSnapshot, now: Date, inheritedTagMask: Int?, folderState: UInt8?) -> Bool {
        if includeTags != 0 || excludeTags != 0 {
            let tagMask: Int = inheritedTagMask ?? {
                var mask = 0; var id: Int? = node.id
                while let value = id { let n = snapshot.nodes[value]; mask |= snapshot.tags[n.path] ?? 0; id = n.parent }
                return mask
            }()
            if excludeTags & tagMask != 0 || includeTags != 0 && includeTags & tagMask == 0 { return false }
        }
        let attrs = node.nativeAttributes ?? 0
        if attrs & excludeAttrs != 0 || attrs & includeAttrs != includeAttrs { return false }
        let ads = (node.nativeFlags ?? 0) & 0x10 != 0
        if includeADS && !ads || excludeADS && ads { return false }
        for (metric, range) in bounds {
            let value: Int64
            switch metric {
            case .logical: value = node.logicalBytes
            case .allocated: value = node.allocatedBytes
            case .created, .accessed, .modified:
                let date: Date
                switch metric {
                case .created: date = node.created ?? Self.fileTimeZero
                case .accessed: date = node.accessed ?? Self.fileTimeZero
                default: date = node.modified
                }
                // 0x440810 stores age limits in FILETIME ticks and 0x444870
                // compares before converting to seconds. Preserve Date's
                // subsecond precision rather than truncating a 1.75s age to 1.
                let age = Self.age(now, since: date)
                if let min = range.minimum, age < Double(min) { return false }
                if let max = range.maximum, age > Double(max) { return false }
                continue
            }
            // isIncluded uses inclusive bounds despite the '<' and '>' spellings.
            if let min = range.minimum, value < min { return false }
            if let max = range.maximum, value > max { return false }
        }
        if !folderIncludes.isEmpty || !folderExcludes.isEmpty {
            if let folderState {
                if folderState & 0x40 != 0 || !folderIncludes.isEmpty && folderState & 0x20 == 0 { return false }
            } else {
                var hasFolderMatch = folderIncludes.isEmpty; var parent = node.parent
                while let id = parent {
                    let ancestor = snapshot.nodes[id]
                    if ancestor.nativeType == 1 { parent = ancestor.parent; continue }
                    let segment = ancestor.parent == nil ? ancestor.path : ancestor.name
                    if folderExcludes.contains(where: { $0.matches(segment) }) { return false }
                    if folderIncludes.contains(where: { $0.matches(segment) }) { hasFolderMatch = true }
                    parent = ancestor.parent
                }
                guard hasFolderMatch else { return false }
            }
        }
        return !fileExcludes.contains(where: { $0.matches(node.name) }) && (fileIncludes.isEmpty || fileIncludes.contains { $0.matches(node.name) })
    }
    private static let fileTimeZero = Date(timeIntervalSince1970: -11_644_473_600)
    private static func age(_ now: Date, since date: Date) -> TimeInterval {
        // Native isIncluded compares unsigned FILETIME differences; a future date wraps past all ordinary bounds.
        let seconds = now.timeIntervalSince(date)
        return !seconds.isFinite || seconds < 0 ? .infinity : seconds
    }
    func membership(in snapshot: ScanSnapshot, showHidden: Bool, control: ScanControl? = nil, now: Date = Date()) -> [Bool]? {
        var contexts: [UInt8] = []
        return membership(in: snapshot, showHidden: showHidden, control: control, contexts: &contexts, now: now)
    }
    func membership(in snapshot: ScanSnapshot, showHidden: Bool, control: ScanControl?, contexts: inout [UInt8], now: Date = Date()) -> [Bool]? {
        if isEmpty && showHidden {
            guard control?.isCancelled != true else { return nil }
            return Array(repeating: true, count: snapshot.nodes.count)
        }
        var result = Array(repeating: false, count: snapshot.nodes.count)
        let usesTags = includeTags != 0 || excludeTags != 0
        let usesFolders = !folderIncludes.isEmpty || !folderExcludes.isEmpty
        let needsContext = usesTags || usesFolders || !showHidden
        // Four tag bits, inherited-hidden, positive-folder and negative-folder
        // flags fit in one byte per node. Allocate nothing for unused contexts.
        if needsContext {
            if contexts.isEmpty { contexts = Array(repeating: 0, count: result.count) }
            else if contexts.count < result.count { contexts.append(contentsOf: repeatElement(0, count: result.count - contexts.count)) }
            else if contexts.count > result.count { contexts.removeLast(contexts.count - result.count) }
        }
        // macOS immutable evaluation uses one explicit timestamp for this pass.
        // Native updateFiltering 0x46a490 captures per recursive parent invocation;
        // the FILETIME comparison itself is shared, not that clock-sampling scope.
        for node in snapshot.nodes {
            if node.id % 1024 == 0 && control?.isCancelled == true { return nil }
            let inherited = needsContext ? node.parent.map { contexts[$0] } ?? 0 : 0
            var state = inherited
            if usesTags { state |= UInt8(truncatingIfNeeded: snapshot.tags[node.path] ?? 0) & 15 }
            if !showHidden && (node.nativeAttributes ?? 0) & 2 != 0 { state |= 0x10 }
            result[node.id] = state & 0x10 == 0 && (isEmpty || !node.isDirectory && evaluate(node, snapshot: snapshot, now: now,
                inheritedTagMask: Int(state & 15), folderState: inherited))
            if usesFolders && node.isDirectory && node.nativeType != 1 {
                let segment = node.parent == nil ? node.path : node.name
                if state & 0x20 == 0 && folderIncludes.contains(where: { $0.matches(segment) }) { state |= 0x20 }
                if state & 0x40 == 0 && folderExcludes.contains(where: { $0.matches(segment) }) { state |= 0x40 }
            }
            if needsContext { contexts[node.id] = state }
        }
        return result
    }
    public func matchingIDs(in snapshot: ScanSnapshot, showHidden: Bool = true, root: Int = 0) -> [Int] {
        guard snapshot.nodes.indices.contains(root), var included = membership(in: snapshot, showHidden: showHidden) else { return [] }
        if included.count > 1 {
            for i in stride(from: included.count - 1, through: 1, by: -1) {
                if included[i], let parent = snapshot.nodes[i].parent { included[parent] = true }
            }
        }
        var ids: [Int] = []; var stack = [root]
        while let id = stack.popLast() {
            if included[id] { ids.append(id); stack.append(contentsOf: snapshot.nodes[id].children.reversed()) }
        }
        return ids
    }
    public func weights(in snapshot: ScanSnapshot, mode: SizeMode, showHidden: Bool = true, control: ScanControl? = nil) -> [Int64] {
        guard let included = membership(in: snapshot, showHidden: showHidden, control: control) else { return [] }
        return weights(in: snapshot, mode: mode, included: included, control: control)
    }
    func weights(in snapshot: ScanSnapshot, mode: SizeMode, included: [Bool], control: ScanControl? = nil,
                 leafCheckpoint: ((Int) -> Void)? = nil) -> [Int64] {
        guard control?.isCancelled != true else { return [] }
        var result = Array(repeating: Int64(0), count: snapshot.nodes.count)
        for id in snapshot.nodes.indices {
            if id % 1024 == 0 {
                leafCheckpoint?(id)
                if control?.isCancelled == true { return [] }
            }
            let node = snapshot.nodes[id]
            if !node.isDirectory && included[id] { result[id] = node.bytes(mode) }
        }
        if result.count > 1 {
            for i in stride(from: result.count - 1, through: 1, by: -1) {
                if i % 1024 == 0 && control?.isCancelled == true { return [] }
                if let parent = snapshot.nodes[i].parent { result[parent] += result[i] }
            }
        }
        return result
    }
}
public enum FilterError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(value) = self { return "원본 필터 문법을 확인하세요: \(value)" }; return nil }
}
