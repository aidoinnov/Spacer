import SpaceSnifferCore

/// A snapshot-scoped accounting observation, never a scan-completion estimate.
public enum SpaceAccountingPayload {
    public static func make(snapshot: ScanSnapshot?, offline: Bool) -> JSONValue {
        guard let snapshot, let accounting = SpaceAccounting(snapshot: snapshot, offline: offline) else { return .null }
        return .object([
            "scope": .string("live_volume_snapshot"),
            "volume_metadata_timing": .string("captured_at_scan_start"),
            "total_bytes": .integer(accounting.totalBytes),
            "free_bytes": .integer(accounting.freeBytes),
            "system_used_bytes": .integer(accounting.systemUsedBytes),
            "observed_physical_bytes": .integer(accounting.observedPhysicalBytes),
            "unattributed_bytes": .integer(accounting.unattributedBytes),
            "unclamped_residual_bytes": accounting.unclampedResidualBytes.map(JSONValue.integer) ?? .null,
            "diagnostics": .array(accounting.diagnostics.map { .string($0.rawValue) }),
            "coverage_percentage_available": .bool(false)
        ])
    }
}
