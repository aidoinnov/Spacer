// Appended to a frozen Filter.swift only by r05-build-probe.py.
// This is a measurement prototype, never linked into the production target.
struct R05Evaluation {
    let included: [Bool]
    let weights: [Int64]
    let focusIDs: [Int]
    let ancestorContexts: Int
}

extension ScanFilter {
    @inline(never) func r05FocusFirst(in snapshot: ScanSnapshot, mode: SizeMode, showHidden: Bool,
        focus: Int, now: Date, control: ScanControl,
        onFocus: ([Bool], [Int64]) -> Void) -> R05Evaluation? {
        guard snapshot.nodes.indices.contains(focus), !control.isCancelled else { return nil }
        let uniform = isEmpty && showHidden
        let usesTags = includeTags != 0 || excludeTags != 0
        let usesFolders = !folderIncludes.isEmpty || !folderExcludes.isEmpty
        let needsContext = usesTags || usesFolders || !showHidden
        var included = Array(repeating: uniform, count: snapshot.nodes.count)
        var weights = Array(repeating: Int64(0), count: snapshot.nodes.count)
        var contexts = needsContext ? Array(repeating: UInt8(0), count: snapshot.nodes.count) : []
        var visited = Array(repeating: false, count: snapshot.nodes.count)

        // The focus ancestor chain is computed once, not once per leaf.
        func state(after node: DiskNode, inherited: UInt8) -> UInt8 {
            var state = inherited
            if usesTags { state |= UInt8(truncatingIfNeeded: snapshot.tags[node.path] ?? 0) & 15 }
            if !showHidden && (node.nativeAttributes ?? 0) & 2 != 0 { state |= 0x10 }
            if usesFolders && node.isDirectory && node.nativeType != 1 {
                let segment = node.parent == nil ? node.path : node.name
                if state & 0x20 == 0 && folderIncludes.contains(where: { $0.matches(segment) }) { state |= 0x20 }
                if state & 0x40 == 0 && folderExcludes.contains(where: { $0.matches(segment) }) { state |= 0x40 }
            }
            return state
        }
        func process(_ node: DiskNode) {
            let inherited = needsContext ? node.parent.map { contexts[$0] } ?? 0 : 0
            let current = needsContext ? state(after: node, inherited: inherited) : 0
            let match = uniform || current & 0x10 == 0 && (isEmpty || !node.isDirectory &&
                evaluate(node, snapshot: snapshot, now: now, inheritedTagMask: Int(current & 15), folderState: inherited))
            if !uniform { included[node.id] = match }
            if !node.isDirectory && match { weights[node.id] = node.bytes(mode) }
            if needsContext { contexts[node.id] = current }
        }
        var ancestors: [Int] = []
        if needsContext {
            var parent = snapshot.nodes[focus].parent
            while let id = parent {
                if control.isCancelled { return nil }
                ancestors.append(id); parent = snapshot.nodes[id].parent
            }
            for id in ancestors.reversed() {
                let node = snapshot.nodes[id]
                contexts[id] = state(after: node, inherited: node.parent.map { contexts[$0] } ?? 0)
            }
        }
        var order: [Int] = []; var stack = [focus]
        while let id = stack.popLast() {
            if order.count % 1024 == 0 && control.isCancelled { return nil }
            let node = snapshot.nodes[id]
            visited[id] = true; process(node); order.append(id)
            stack.append(contentsOf: node.children.reversed())
        }
        for (offset, id) in order.reversed().enumerated() {
            if offset % 1024 == 0 && control.isCancelled { return nil }
            if id != focus, let parent = snapshot.nodes[id].parent { weights[parent] += weights[id] }
        }
        guard !control.isCancelled else { return nil }
        onFocus(included, weights)
        guard !control.isCancelled else { return nil }
        for node in snapshot.nodes {
            if node.id % 1024 == 0 && control.isCancelled { return nil }
            if !visited[node.id] { process(node) }
        }
        if snapshot.nodes.count > 1 {
            for id in stride(from: snapshot.nodes.count - 1, through: 1, by: -1) {
                if id % 1024 == 0 && control.isCancelled { return nil }
                // Internal focus edges were already aggregated before publish.
                if (!visited[id] || id == focus), let parent = snapshot.nodes[id].parent { weights[parent] += weights[id] }
            }
        }
        guard !control.isCancelled else { return nil }
        return R05Evaluation(included: included, weights: weights, focusIDs: order, ancestorContexts: ancestors.count)
    }

    /// Controls for loop fusion independently of the focus ordering benefit.
    @inline(never) func r05Fused(in snapshot: ScanSnapshot, mode: SizeMode, showHidden: Bool,
        now: Date, control: ScanControl) -> R05Evaluation? {
        guard !control.isCancelled else { return nil }
        let uniform = isEmpty && showHidden
        let usesTags = includeTags != 0 || excludeTags != 0
        let usesFolders = !folderIncludes.isEmpty || !folderExcludes.isEmpty
        let needsContext = usesTags || usesFolders || !showHidden
        var included = Array(repeating: uniform, count: snapshot.nodes.count)
        var weights = Array(repeating: Int64(0), count: snapshot.nodes.count)
        var contexts = needsContext ? Array(repeating: UInt8(0), count: snapshot.nodes.count) : []
        for node in snapshot.nodes {
            if node.id % 1024 == 0 && control.isCancelled { return nil }
            let inherited = needsContext ? node.parent.map { contexts[$0] } ?? 0 : 0
            var state = inherited
            if usesTags { state |= UInt8(truncatingIfNeeded: snapshot.tags[node.path] ?? 0) & 15 }
            if !showHidden && (node.nativeAttributes ?? 0) & 2 != 0 { state |= 0x10 }
            let match = uniform || state & 0x10 == 0 && (isEmpty || !node.isDirectory &&
                evaluate(node, snapshot: snapshot, now: now, inheritedTagMask: Int(state & 15), folderState: inherited))
            if !uniform { included[node.id] = match }
            if !node.isDirectory && match { weights[node.id] = node.bytes(mode) }
            if usesFolders && node.isDirectory && node.nativeType != 1 {
                let segment = node.parent == nil ? node.path : node.name
                if state & 0x20 == 0 && folderIncludes.contains(where: { $0.matches(segment) }) { state |= 0x20 }
                if state & 0x40 == 0 && folderExcludes.contains(where: { $0.matches(segment) }) { state |= 0x40 }
            }
            if needsContext { contexts[node.id] = state }
        }
        if snapshot.nodes.count > 1 {
            for id in stride(from: snapshot.nodes.count - 1, through: 1, by: -1) {
                if id % 1024 == 0 && control.isCancelled { return nil }
                if let parent = snapshot.nodes[id].parent { weights[parent] += weights[id] }
            }
        }
        guard !control.isCancelled else { return nil }
        return R05Evaluation(included: included, weights: weights, focusIDs: [], ancestorContexts: 0)
    }
}
