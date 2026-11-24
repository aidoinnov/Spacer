/// One actual native query. No path strings or unbounded event log retained.
struct EntryCountObservation: Sendable {
    let elapsedNanoseconds: UInt64
    let errorCode: Int32?
    let unavailableResult: Bool
    let cancelledAfterCall: Bool
}

/// Scan-local diagnostics. An absent block in old reports means unmeasured,
/// not zero queries. Native querying and admission decisions remain separate.
struct EntryCountMetrics: Codable, Sendable, Equatable {
    var calls = 0
    var failures = 0
    var unavailableResults = 0
    var cancelledAfterCall = 0
    var elapsedNanoseconds: UInt64 = 0
    var admissionCandidatesExamined = 0
    var admissionHintHits = 0

    mutating func record(_ observation: EntryCountObservation) {
        calls += 1
        if observation.errorCode != nil { failures += 1 }
        if observation.unavailableResult { unavailableResults += 1 }
        if observation.cancelledAfterCall { cancelledAfterCall += 1 }
        elapsedNanoseconds += observation.elapsedNanoseconds
    }
    mutating func merge(_ other: Self) {
        calls += other.calls; failures += other.failures
        unavailableResults += other.unavailableResults; cancelledAfterCall += other.cancelledAfterCall
        elapsedNanoseconds += other.elapsedNanoseconds
        admissionCandidatesExamined += other.admissionCandidatesExamined
        admissionHintHits += other.admissionHintHits
    }
}
