/// Builder-local admission memory. A negative bounded sample expires, so an
/// early tiny sibling cannot veto later useful work for the whole parent.
public struct DirectorySiblingAdmission<Key: Equatable> {
    private let recheckAfter: Int
    private var parent: Key?
    private var admitted = false
    private var cooldown = 0
    public init(recheckAfter: Int) { precondition(recheckAfter > 0); self.recheckAfter = recheckAfter }
    public mutating func decision(for key: Key) -> Bool? {
        if parent != key { parent = key; admitted = false; cooldown = 0 }
        if admitted { return true }
        if cooldown > 0 { cooldown -= 1; return false }
        return nil
    }
    public mutating func record(_ eligible: Bool, for key: Key) {
        parent = key; admitted = eligible; cooldown = eligible ? 0 : recheckAfter
    }
}
