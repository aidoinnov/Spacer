import Foundation

/// Owns only explicitly hidden automation windows. Normal/closed windows have
/// no lease. Keep the model and native window together until show/close/quit.
@MainActor final class ExplicitWindowRetention<Window: AnyObject, Model: AnyObject> {
    private struct Entry { let window: Window; let model: Model }
    private var entries: [String: Entry] = [:]
    private var active = false
    private let begin: @Sendable () -> Void
    private let end: @Sendable () -> Void
    init(begin: @escaping @Sendable () -> Void = { ProcessInfo.processInfo.disableAutomaticTermination("MCP explicitly hidden window") },
         end: @escaping @Sendable () -> Void = { ProcessInfo.processInfo.enableAutomaticTermination("MCP explicitly hidden window") }) {
        self.begin = begin; self.end = end
    }
    var hasWindows: Bool { !entries.isEmpty }
    var count: Int { entries.count }
    func contains(_ id: String) -> Bool { entries[id] != nil }
    func retain(_ id: String, window: Window, model: Model) {
        if !active { active = true; begin() }
        entries[id] = Entry(window: window, model: model)
    }
    func release(_ id: String) {
        entries[id] = nil
        if active && entries.isEmpty { active = false; end() }
    }
    func removeAll() { entries.removeAll(); if active { active = false; end() } }
    deinit { if active { end() } }
}
