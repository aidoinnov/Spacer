import Foundation

/// An owner-scoped intent, not an independent worker or a frozen snapshot.
/// Exact tickets make cancellation safe after owner replacement/root recreation.
public struct FocusScanRequest: Hashable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let rootPath: String
    public let scope: String
    public let rootIncarnation: UUID
    let targetIdentity: String?
}

/// Latest intent per owner plus stable FIFO admission. Execution stays serialized
/// in ScanService. Native 0x430270 has a view-owned focus slot; 0x406b10 guards
/// the same target node. This policy does not claim native parallel equivalence.
struct FocusScanRequests {
    let rootPath: String
    let incarnation: UUID
    private var latest: [UUID: FocusScanRequest] = [:]
    private var owners: [UUID] = []
    private(set) var active: FocusScanRequest?

    init(rootPath: String, incarnation: UUID) { self.rootPath = rootPath; self.incarnation = incarnation }
    var isEmpty: Bool { owners.isEmpty }
    mutating func replace(owner: UUID, scope: String, targetIdentity: String?) -> FocusScanRequest {
        let request = FocusScanRequest(id: UUID(), ownerID: owner, rootPath: rootPath, scope: scope,
                                       rootIncarnation: incarnation, targetIdentity: targetIdentity)
        latest[owner] = request
        if !owners.contains(owner) { owners.append(owner) }
        return request
    }
    func isCurrent(_ request: FocusScanRequest) -> Bool {
        request.rootIncarnation == incarnation && latest[request.ownerID] == request
    }
    mutating func takeNext() -> FocusScanRequest? {
        guard active == nil else { return nil }
        while !owners.isEmpty {
            let owner = owners.removeFirst()
            if let request = latest[owner] { active = request; return request }
        }
        return nil
    }
    mutating func finish(_ request: FocusScanRequest) {
        guard active == request else { return }
        active = nil
        if latest[request.ownerID] == request { latest.removeValue(forKey: request.ownerID) }
    }
    /// Returns true only if this owner's active job needs cancellation. The job
    /// remains active until its completion is drained, so another cannot overlap.
    @discardableResult mutating func cancel(owner: UUID) -> Bool {
        latest.removeValue(forKey: owner); owners.removeAll { $0 == owner }
        return active?.ownerID == owner
    }
    @discardableResult mutating func cancel(_ request: FocusScanRequest) -> Bool {
        guard isCurrent(request) else { return false }
        return cancel(owner: request.ownerID)
    }
    mutating func reset() {
        latest.removeAll(); owners.removeAll()
        // Keep active until terminal cleanup. It is now obsolete and cannot commit.
    }
}
