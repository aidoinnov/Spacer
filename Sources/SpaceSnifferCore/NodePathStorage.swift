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
    public static func == (lhs: Self, rhs: Self) -> Bool {
        if let l = lhs.leaf, let r = rhs.leaf, lhs.base == rhs.base, l == r { return true }
        return lhs.wrappedValue == rhs.wrappedValue
    }
}
