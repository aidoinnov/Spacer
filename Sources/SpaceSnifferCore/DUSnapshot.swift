import Foundation

/// Strict import adapter for SpaceSniffer's .DU text reader (canonical 0x4547f0).
/// ASCII space separates KiB from a Windows backslash path; dots are numeric grouping.
/// This is not the unrelated Sysinternals CSV or Unix du grammar.
public enum DUSnapshot {
    public struct Limits: Sendable {
        public var maximumBytes: Int
        public var maximumRecords: Int
        public var maximumNodes: Int
        public var maximumDepth: Int
        public init(maximumBytes: Int = 64 * 1024 * 1024, maximumRecords: Int = 1_000_000,
                    maximumNodes: Int = 2_000_000, maximumDepth: Int = 256) {
            self.maximumBytes = maximumBytes; self.maximumRecords = maximumRecords
            self.maximumNodes = maximumNodes; self.maximumDepth = maximumDepth
        }
    }
    public enum FormatError: LocalizedError, Equatable {
        case empty, limitExceeded, malformedLine(Int), invalidPath(Int), numericOverflow(Int)
        case inconsistentTotals(Int), ambiguousResidual(Int), rootSelectionRequired(Int), invalidRootIndex
        public var errorDescription: String? {
            switch self {
            case .empty: "DU 스냅샷에 읽을 기록이 없습니다."
            case .limitExceeded: "DU 스냅샷이 설정한 크기·기록·노드·깊이 한도를 넘었습니다."
            case let .malformedLine(line): "DU 스냅샷 \(line)행의 KiB 크기와 경로 형식이 잘못되었습니다."
            case let .invalidPath(line): "DU 스냅샷 \(line)행에 지원하지 않는 경로가 있습니다."
            case let .numericOverflow(line): "DU 스냅샷 \(line)행의 크기 합계가 Int64 범위를 넘습니다."
            case let .inconsistentTotals(line): "DU 스냅샷 \(line)행의 하위 크기가 남은 상위 크기보다 큽니다."
            case let .ambiguousResidual(line): "DU 스냅샷 \(line)행의 Files 누락 기록을 모호함 없이 표현할 수 없습니다."
            case let .rootSelectionRequired(count): "이 DU에는 루트가 \(count)개 있습니다. 열 루트를 선택하세요."
            case .invalidRootIndex: "선택한 DU 루트가 없습니다."
            }
        }
    }
    private static func checkpoint(_ control: ScanControl?) throws {
        if Task.isCancelled || control?.isCancelled == true { throw CancellationError() }
    }
    /// Native accepts() 0x4546a0 checks the last three characters, uppercased, against .DU.
    public static func accepts(filename: String) -> Bool {
        filename.count > 3 && filename.suffix(3).uppercased() == ".DU"
    }
    public static func decode(_ data: Data, legacyCodePage: UInt32? = nil, rootIndex: Int? = nil,
                              limits: Limits = Limits(), control: ScanControl? = nil) throws -> ScanSnapshot {
        let roots = try decodeAll(data, legacyCodePage: legacyCodePage, limits: limits, control: control)
        if let rootIndex {
            guard roots.indices.contains(rootIndex) else { throw FormatError.invalidRootIndex }
            return roots[rootIndex]
        }
        guard roots.count == 1 else { throw FormatError.rootSelectionRequired(roots.count) }
        return roots[0]
    }
    public static func decodeAll(_ data: Data, legacyCodePage: UInt32? = nil,
                                 limits: Limits = Limits(), control: ScanControl? = nil) throws -> [ScanSnapshot] {
        try checkpoint(control)
        guard limits.maximumBytes > 0, limits.maximumRecords > 0, limits.maximumNodes > 0,
              limits.maximumDepth > 0, data.count <= limits.maximumBytes else { throw FormatError.limitExceeded }
        guard !data.isEmpty else { throw FormatError.empty }
        // Original _wfopen(...,"r") + fgetws uses Windows CRT text conversion. Never guess ACP.
        let text = try WindowsLegacyText.decode(data, codePage: legacyCodePage)
        try checkpoint(control)
        guard !text.contains("\0") else { throw FormatError.malformedLine(1) }
        var builder = Builder(limits: limits, control: control)
        var count = 0
        // Swift treats CRLF as one Character; splitting only on LF would leave
        // an entire Windows text file inside a single path record.
        let lines = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
        for (index, raw) in lines.enumerated() {
            try checkpoint(control)
            if index == lines.count - 1 && raw.isEmpty { continue }
            let number = index + 1
            count += 1
            guard count <= limits.maximumRecords, raw.utf16.count <= 8190 else { throw FormatError.limitExceeded }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: " ") else { throw FormatError.malformedLine(number) }
            let numeric = line[..<separator]
            // Native strips all dots then atoi64. This adapter rejects signs, empty groups,
            // and atoi64's accepted junk suffixes instead of importing silently truncated totals.
            let groups = numeric.split(separator: ".", omittingEmptySubsequences: false)
            guard groups.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else {
                throw FormatError.malformedLine(number)
            }
            var kib: Int64 = 0
            for byte in numeric.utf8 where byte != 46 {
                let times = kib.multipliedReportingOverflow(by: 10)
                let next = times.partialValue.addingReportingOverflow(Int64(byte - 48))
                guard !times.overflow, !next.overflow else { throw FormatError.numericOverflow(number) }
                kib = next.partialValue
            }
            let bytes = kib.multipliedReportingOverflow(by: 1024)
            guard !bytes.overflow else { throw FormatError.numericOverflow(number) }
            let path = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            try builder.add(path: path, bytes: bytes.partialValue, line: number)
        }
        guard count > 0 else { throw FormatError.empty }
        return try builder.snapshots()
    }

    private struct Entry {
        var name: String
        var path: String
        var parent: Int?
        var children: [Int] = []
        var folders: [[UInt16]: Int] = [:]
        var missing: Int?
        var bytes: Int64 = 0
        var isMissing = false
        var removed = false
    }
    private struct Builder {
        let limits: Limits
        let control: ScanControl?
        var entries: [Entry] = []
        var roots: [Int] = []
        var drives: [String: Int] = [:]
        mutating func append(_ entry: Entry) throws -> Int {
            try checkpoint(control)
            guard entries.count < limits.maximumNodes else { throw FormatError.limitExceeded }
            let index = entries.count; entries.append(entry)
            if let parent = entry.parent { entries[parent].children.append(index) }
            return index
        }
        mutating func delta(_ id: Int, _ amount: Int64, line: Int) throws {
            var current: Int? = id
            while let value = current {
                try checkpoint(control)
                let sum = entries[value].bytes.addingReportingOverflow(amount)
                guard !sum.overflow else { throw FormatError.numericOverflow(line) }
                guard sum.partialValue >= 0 else { throw FormatError.inconsistentTotals(line) }
                entries[value].bytes = sum.partialValue
                current = entries[value].parent
            }
        }
        mutating func residual(_ parent: Int, _ amount: Int64, line: Int) throws {
            // Native can create repeated identically named missing records. Refuse this ambiguous
            // shape rather than merging records and changing later getChildByFlag subtraction.
            guard entries[parent].missing == nil, entries[parent].folders[Array("Files".utf16)] == nil else {
                throw FormatError.ambiguousResidual(line)
            }
            let id = try append(Entry(name: "Files", path: SnapshotPath.join(entries[parent].path, "Files"),
                                      parent: parent, isMissing: true))
            entries[parent].missing = id
            try delta(id, amount, line: line)
        }
        mutating func add(path: String, bytes: Int64, line: Int) throws {
            let units = Array(path.utf16)
            guard units.count >= 3, ((65...90).contains(units[0]) || (97...122).contains(units[0])),
                  units[1] == 58, units[2] == 92, !path.contains("/"), !path.contains("\t"),
                  path.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
                throw FormatError.invalidPath(line)
            }
            let drive = String(UnicodeScalar(UInt32(units[0]))!) + ":\\"
            let suffix = String(path.dropFirst(3))
            let components = suffix.isEmpty ? [] : suffix.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
            guard components.count <= limits.maximumDepth,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") && !$0.contains("\"") }) else {
                throw FormatError.invalidPath(line)
            }
            let wasNewRoot = drives[drive] == nil
            let root: Int
            if let existing = drives[drive] { root = existing }
            else {
                root = try append(Entry(name: String(drive.prefix(2)), path: drive, parent: nil))
                drives[drive] = root; roots.append(root)
            }
            var current = root
            var finalWasNew = components.isEmpty && wasNewRoot
            for (index, component) in components.enumerated() {
                try checkpoint(control)
                let key = Array(component.utf16)
                if let existing = entries[current].folders[key] {
                    current = existing; finalWasNew = false
                } else {
                    guard component != "Files" || entries[current].missing == nil else { throw FormatError.ambiguousResidual(line) }
                    let child = try append(Entry(name: component, path: SnapshotPath.join(entries[current].path, component), parent: current))
                    entries[current].folders[key] = child
                    current = child; finalWasNew = index == components.count - 1
                }
            }
            if finalWasNew {
                try residual(current, bytes, line: line)
                if let parent = entries[current].parent, let missing = entries[parent].missing {
                    guard entries[missing].bytes >= bytes else { throw FormatError.inconsistentTotals(line) }
                    try delta(missing, -bytes, line: line)
                    if entries[missing].bytes == 0 {
                        entries[missing].removed = true; entries[parent].missing = nil
                    }
                }
            } else if entries[current].bytes < bytes {
                try residual(current, bytes - entries[current].bytes, line: line)
            }
        }
        func snapshots() throws -> [ScanSnapshot] {
            try roots.map { root in
                try checkpoint(control)
                var snapshot = ScanSnapshot(rootPath: entries[root].path)
                var mapping: [Int: Int] = [:]
                var stack = [root]
                // Rebuild IDs in parent-before-child DFS order after residual removal.
                while let old = stack.popLast() {
                    try checkpoint(control)
                    let entry = entries[old]
                    guard !entry.removed else { continue }
                    let id = snapshot.nodes.count; mapping[old] = id
                    let parent = entry.parent.flatMap { mapping[$0] }
                    var node = DiskNode(id: id, parent: parent, path: entry.path, name: entry.name,
                                        isDirectory: !entry.isMissing, logicalBytes: entry.bytes, allocatedBytes: entry.bytes)
                    node.nativeType = entry.isMissing ? 6 : 3
                    node.ownAllocatedBytes = entry.isMissing ? entry.bytes : 0
                    snapshot.nodes.append(node)
                    if let parent { snapshot.nodes[parent].children.append(id) }
                    if !entry.isMissing { snapshot.folderCount += 1 }
                    stack.append(contentsOf: entry.children.reversed())
                }
                snapshot.finished = Date()
                try checkpoint(control)
                // Builder enforces parent-before-child IDs, balanced sums and nonnegative sizes.
                // Avoid a second uncancellable whole-table Model.validated pass here.
                return snapshot
            }
        }
    }
}
