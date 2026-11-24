import Foundation
import CoreServices

public struct PathChange: Sendable {
    public let path: String
    public let isDirectory: Bool
    public let mustRescan: Bool
}

/// FSEvents has its own serial utility queue. Only copied event values cross into the cache actor.
final class DirectoryMonitor: @unchecked Sendable {
    private final class Callback: Sendable {
        let root: String
        let action: @Sendable ([PathChange]) -> Void
        init(root: String, action: @escaping @Sendable ([PathChange]) -> Void) {
            self.root = root; self.action = action
        }
    }
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "local.macspacesniffer.watch", qos: .utility)
    static var nowCursor:FSEventStreamEventId {FSEventStreamEventId(kFSEventStreamEventIdSinceNow)}
    static func eventCursor()->FSEventStreamEventId? {
        let value=FSEventsGetCurrentEventId();return value == 0 ? nil : value
    }
    init?(path: String, since: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow), action: @escaping @Sendable ([PathChange]) -> Void) {
        let callback = Callback(root: path, action: action)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Callback>.fromOpaque(info).retain(); return info
            }, release: { info in
                if let info { Unmanaged<Callback>.fromOpaque(info).release() }
            }, copyDescription: nil)
        let handler: FSEventStreamCallback = { stream, info, count, paths, flags, _ in
            WorkerTelemetry.shared.record("watch.events")
            guard let info else { return }
            let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
            // The stream retains its native root spelling from creation. Read
            // that cached value once per batch, never resolve a removed item or
            // perform per-event realpath I/O on the service actor.
            let watched = FSEventStreamCopyPathsBeingWatched(stream) as NSArray
            guard let nativeRoot = watched.firstObject as? String else {
                callback.action([PathChange(path: callback.root, isDirectory: true, mustRescan: true)])
                return
            }
            let eventPath = DirectoryWatchPath(root: callback.root, nativeRoot: nativeRoot)
            let names = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let lossMask = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs |
                kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped |
                kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagEventIdsWrapped |
                kFSEventStreamEventFlagUnmount | kFSEventStreamEventFlagMount)
            let events = (0..<min(count, names.count)).compactMap { index -> PathChange? in
                guard flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) == 0 || flags[index] & lossMask != 0 else {return nil}
                return PathChange(path: eventPath.map(names[index]), isDirectory: flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0,
                    mustRescan: flags[index] & lossMask != 0)
            }
            callback.action(events)
        }
        stream = FSEventStreamCreate(nil, handler, &context, [path] as CFArray,
            since, 0.05,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { return nil }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil; return nil
        }
    }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
