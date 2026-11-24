import Foundation

protocol DirectoryWatchState: AnyObject { var watchActive: Bool { get } }

/// FSEvents registration/teardown may block in OS I/O. Neither operation runs
/// on ScanService's actor. One registration lane bounds blocked native threads.
final class DirectoryMonitorRegistration: DirectoryWatchState, @unchecked Sendable {
    private final class Owner: @unchecked Sendable {
        let value: AnyObject
        init(_ value: AnyObject) { self.value=value }
    }
    private final class State: @unchecked Sendable {
        let lock=NSLock()
        var cancelled=false
        var owner:Owner?
        var active:Bool {lock.lock(); defer {lock.unlock()}; return owner != nil}
        var shouldCreate:Bool {lock.lock(); defer {lock.unlock()}; return !cancelled}
        func install(_ value:Owner)->Bool {
            lock.lock(); defer {lock.unlock()}
            guard !cancelled else {return false}; owner=value; return true
        }
        func cancel()->Owner? {
            lock.lock(); defer {lock.unlock()}
            cancelled=true; let previous=owner; owner=nil; return previous
        }
    }
    private static let registrationQueue=DispatchQueue(label:"local.macspacesniffer.watch.registration",qos:.utility)
    private static let releaseQueue=DispatchQueue(label:"local.macspacesniffer.watch.release",qos:.utility)
    private let state=State()
    var watchActive:Bool {state.active}
    init(create:@escaping @Sendable()->AnyObject?, ready:@escaping @Sendable()->Void) {
        let state=self.state
        Self.registrationQueue.async {
            guard state.shouldCreate, let native=create() else {return}
            let owner=Owner(native)
            if state.install(owner) {ready()}
            // A cancelled registration's native object is released on this lane.
        }
    }
    deinit {
        if let owner=state.cancel() {
            Self.releaseQueue.async {withExtendedLifetime(owner) {}}
        }
    }
}
