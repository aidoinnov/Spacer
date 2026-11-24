import AppKit

/// NotificationCenter removal is thread-safe; the token is immutable after init.
final class NotificationLease: @unchecked Sendable {
    private let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Owns bounded native observation only; no render data or Store ownership.
@MainActor
final class MapWindowLifecycle {
    private var leases: [NotificationLease] = []
    private var generation = UUID()
    var observerCount: Int { leases.count }
    func unbind() { generation = UUID(); leases.removeAll() }
    func bind(_ window: NSWindow?, changed: @escaping @MainActor @Sendable (Bool) -> Void) {
        unbind(); guard let window else { return }; let token = generation
        let names = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification]
        for name in names {
            let closing = name == NSWindow.willCloseNotification
            leases.append(NotificationLease(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if closing { self.unbind() }
                    changed(closing)
                }
            }))
        }
    }
}
