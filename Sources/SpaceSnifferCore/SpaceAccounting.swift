import Foundation

/// Pure whole-volume accounting from TDriveNode getUsedSize/getUnknownSize
/// (0x404cb0/0x404880). These values are separate from file-path contributions:
/// live free/unknown filesystem nodes return zero (0x40a750/0x40ad80).
public struct SpaceAccounting: Equatable, Sendable {
    public enum Diagnostic: String, Equatable, Sendable {
        case zeroCapacity = "zero_capacity"
        case freeExceedsTotal = "free_exceeds_total"
        case observedExceedsUsed = "observed_exceeds_used"
        case residualUnderflow = "residual_underflow"
    }
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let observedPhysicalBytes: Int64
    /// Native used = total - free. An inconsistent OS sample can be negative;
    /// retain that fact instead of disguising it as successful reconciliation.
    public let systemUsedBytes: Int64
    public let unclampedResidualBytes: Int64?
    public let unattributedBytes: Int64
    public let diagnostics: [Diagnostic]

    /// Negative byte inputs are invalid. Arithmetic diagnostics are Mac guards,
    /// not evidence of what Windows does with impossible signed-overflow input.
    public init?(totalBytes: Int64, freeBytes: Int64, observedPhysicalBytes: Int64) {
        guard totalBytes >= 0, freeBytes >= 0, observedPhysicalBytes >= 0 else { return nil }
        self.totalBytes = totalBytes; self.freeBytes = freeBytes; self.observedPhysicalBytes = observedPhysicalBytes
        let used = totalBytes - freeBytes // Nonnegative operands cannot overflow this subtraction.
        systemUsedBytes = used
        let residual = used.subtractingReportingOverflow(observedPhysicalBytes)
        unclampedResidualBytes = residual.overflow ? nil : residual.partialValue
        // Evaluate max(0, total-free-observed) mathematically without allowing
        // a negative residual to wrap into a positive fictional allocation.
        unattributedBytes = used > observedPhysicalBytes ? used - observedPhysicalBytes : 0
        var flags: [Diagnostic] = []
        if totalBytes == 0 { flags.append(.zeroCapacity) }
        if freeBytes > totalBytes { flags.append(.freeExceedsTotal) }
        if observedPhysicalBytes > used { flags.append(.observedExceedsUsed) }
        if residual.overflow { flags.append(.residualUnderflow) }
        diagnostics = flags
    }

    /// Only a live volume-root scan has compatible OS and observed-data scope.
    /// Offline SNS type4/5/6 stored values must never enter this live formula.
    public init?(snapshot: ScanSnapshot, offline: Bool) {
        guard !offline, snapshot.isVolumeRoot, snapshot.volumeCoverage?.traversal != .allVolumes,
              let root = snapshot.nodes.first else { return nil }
        self.init(totalBytes: snapshot.volumeTotal, freeBytes: snapshot.volumeFree, observedPhysicalBytes: root.allocatedBytes)
    }

    /// Native view visibility requires an explicit switch and a void filter
    /// (0x42f6b0/0x42f6f0). Keep these presentation-only contributions separate
    /// from the observed data aggregate. The caller supplies actual filtered
    /// data bytes when a filter is active; default is the unfiltered aggregate.
    public func presentation(isVoidFilter: Bool, showFreeSpace: Bool, showUnknownSpace: Bool,
                             dataPhysicalBytes: Int64? = nil) -> SpaceAccountingPresentation? {
        let data = dataPhysicalBytes ?? observedPhysicalBytes
        guard data >= 0 else { return nil }
        return SpaceAccountingPresentation(dataPhysicalBytes: data,
            freeSpaceBytes: isVoidFilter && showFreeSpace ? freeBytes : 0,
            unattributedSpaceBytes: isVoidFilter && showUnknownSpace ? unattributedBytes : 0)
    }
}

public struct SpaceAccountingPresentation: Equatable, Sendable {
    public let dataPhysicalBytes: Int64
    public let freeSpaceBytes: Int64
    public let unattributedSpaceBytes: Int64
    /// A caller must not use a wrapped area as a treemap denominator.
    public let totalAreaBytes: Int64?
    public var overflowed: Bool { totalAreaBytes == nil }

    fileprivate init(dataPhysicalBytes: Int64, freeSpaceBytes: Int64, unattributedSpaceBytes: Int64) {
        self.dataPhysicalBytes = dataPhysicalBytes; self.freeSpaceBytes = freeSpaceBytes
        self.unattributedSpaceBytes = unattributedSpaceBytes
        let first = dataPhysicalBytes.addingReportingOverflow(freeSpaceBytes)
        let second = first.partialValue.addingReportingOverflow(unattributedSpaceBytes)
        totalAreaBytes = first.overflow || second.overflow ? nil : second.partialValue
    }
}
