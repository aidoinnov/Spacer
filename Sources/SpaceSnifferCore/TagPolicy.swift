import Foundation

public enum TagPolicy {
    /// Native elementChange action 4 (0x406d30) renames the existing node, preserving its tag.
    /// FSEvents lacks Windows old/new-name pairs. Reconcile a unique *new* path with the same file identity.
    /// Existing hard-link aliases are not rename targets.
    public static func reconcile<Previous: Collection, Current: Collection>(_ tags: [String: Int], previous: Previous, current: Current) -> [String: Int] where Previous.Element == DiskNode, Current.Element == DiskNode {
        guard !tags.isEmpty else { return [:] }
        let paths = survivingPaths(Set(tags.keys), previous: previous, current: current)
        var result: [String: Int] = [:]
        for (path, mask) in tags {
            if let target = paths[path] { result[target, default: 0] |= mask }
        }
        return result
    }

    /// Map only unambiguous new paths. Also used for native stable-node navigation state.
    static func survivingPaths<Previous: Collection, Current: Collection>(_ paths: Set<String>, previous: Previous, current: Current, control: ScanControl? = nil) -> [String: String] where Previous.Element == DiskNode, Current.Element == DiskNode {
        guard !paths.isEmpty else { return [:] }
        var result: [String: String] = [:]
        var currentIdentities: [String: FileIdentity] = [:]
        var currentIDs: [String: Int] = [:]
        let sharedStorage: Bool
        if let before = previous as? NodeTable, let after = current as? NodeTable {
            sharedStorage = before.sharesStorage(with: after)
        } else { sharedStorage = false }
        for node in current {
            if node.id % 1024 == 0 && control?.isCancelled == true { return [:] }
            if paths.contains(node.path) {
                result[node.path] = node.path
                if let identity = node.fileIdentityKey { currentIdentities[node.path] = identity; currentIDs[node.path] = node.id }
                if result.count == paths.count { break }
            }
        }
        if result.count == paths.count && (sharedStorage || currentIdentities.isEmpty) { return result }
        // A path can be deleted and recreated before the next FSEvents scan.
        // When both snapshots identify different objects, the replacement is
        // not the old node whose tag/selection survives. Imported snapshots
        // without identity metadata retain the existing path fallback.
        var identities: [String: FileIdentity] = [:]
        var unchecked = paths
        if let before = previous as? NodeTable {
            // For stable IDs, metadata changes need only the tracked nodes.
            for (path, id) in currentIDs where before.indices.contains(id) && before[id].path == path {
                unchecked.remove(path)
                if let identity = before[id].fileIdentityKey {
                    identities[path] = identity
                    if currentIdentities[path] != identity { result[path] = nil }
                }
            }
        }
        if !unchecked.isEmpty {
            for node in previous {
                if node.id % 1024 == 0 && control?.isCancelled == true { return [:] }
                if unchecked.remove(node.path) != nil, let identity = node.fileIdentityKey {
                    identities[node.path] = identity
                    if let current = currentIdentities[node.path], current != identity { result[node.path] = nil }
                }
                if unchecked.isEmpty { break }
            }
        }
        // The common case (unchanged focus/history/tags) needs no whole-tree index.
        let missing = paths.subtracting(result.keys)
        guard !missing.isEmpty else { return result }
        let neededIdentities = Set(missing.compactMap { identities[$0] })
        guard !neededIdentities.isEmpty else { return result }
        // Keep candidates for tracked identities only, then remove paths that
        // already existed. Existing hard-link aliases must never become rename targets.
        var candidates: [String: FileIdentity] = [:]
        for node in current {
            if node.id % 1024 == 0 && control?.isCancelled == true { return [:] }
            if let identity = node.fileIdentityKey, neededIdentities.contains(identity) { candidates[node.path] = identity }
        }
        for node in previous {
            if node.id % 1024 == 0 && control?.isCancelled == true { return [:] }
            candidates.removeValue(forKey: node.path)
        }
        var newPathsByIdentity: [FileIdentity: [String]] = [:]
        for (path, identity) in candidates { newPathsByIdentity[identity, default: []].append(path) }
        for path in missing {
            if let identity = identities[path],
                    let matches = newPathsByIdentity[identity], matches.count == 1 {
                result[path] = matches[0]
            }
        }
        return result
    }
}
