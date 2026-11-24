import Foundation

/// Native POSIX children share the directory spelling. Literal paths from
/// public callers/imports remain exact, including Windows/UNC and odd roots.
@propertyWrapper
public struct NodePathStorage: Sendable, Equatable {
    private var base: String
    private var leaf: String?
    public init(wrappedValue: String) { base = wrappedValue; leaf = nil }
    init(base: String, leaf: String) { self.base = base; self.leaf = leaf }
    public var wrappedValue: String {
        get { leaf.map { SnapshotPath.joinPOSIX(base, $0) } ?? base }
        set { base = newValue; leaf = nil }
    }
    /// Reuse the node's existing name only when its exact spelling is the leaf.
    /// Arbitrary caller/import paths and mismatched names remain literal data.
    func sharingName(_ name: String) -> (base: String, usesName: Bool) {
        if let leaf, leaf.utf8.elementsEqual(name.utf8) { return (base, true) }
        return (wrappedValue, false)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        if let l = lhs.leaf, let r = rhs.leaf, lhs.base == rhs.base, l == r { return true }
        return lhs.wrappedValue == rhs.wrappedValue
    }
}
