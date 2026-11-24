import Foundation
@testable import SpaceSnifferCore

/// Native addRefilterRequest (0x42e130) keeps unrelated branches in FIFO order,
/// removes descendants covered by an ancestor, and ignores duplicate requests.
/// Here paths replace native node pointers for FSEvents subtree refreshes.
struct LegacyRefreshQueue {
    private(set) var paths: [String] = []
    var isEmpty: Bool { paths.isEmpty }

    mutating func insert(_ path: String) {
        guard !paths.contains(where: { SnapshotTree.contains($0, path) }) else { return }
        removeCovered(by: path)
        paths.append(path)
    }

    mutating func removeCovered(by scope: String) {
        paths.removeAll { SnapshotTree.contains(scope, $0) }
    }

    mutating func popFirst() -> String? {
        guard !paths.isEmpty else { return nil }
        return paths.removeFirst()
    }

    mutating func removeAll() { paths.removeAll() }
}
