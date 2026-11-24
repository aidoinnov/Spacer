import Foundation
#if os(Windows)
import WinSDK
#else
import Darwin
#endif
/// Native owner-death monitoring also works while a codec is synchronously busy.
/// Registration is once per helper, before decoding or starting a scan.
final class ParentLifetime: @unchecked Sendable {
    private final class Registry:@unchecked Sendable {let lock=NSLock();var monitor:ParentLifetime?}
    private static let registry=Registry()
#if os(Windows)
    private let watcher:Thread
#else
    private let watcher:DispatchSourceProcess
#endif
    static func install(_ args:[String]) {
        registry.lock.lock();defer{registry.lock.unlock()}
        guard registry.monitor == nil else {return}
        registry.monitor=ParentLifetime(args)
    }
    private init?(_ args:[String]) {
        guard let index=args.firstIndex(of:"--parent"),args.indices.contains(index+1),let pid=UInt32(args[index+1]),pid>0,pid<=UInt32(Int32.max) else {return nil}
        let output=Self.ownedOutput(args,parent:pid)
#if os(Windows)
        guard let process=OpenProcess(DWORD(SYNCHRONIZE),false,pid) else {Self.finish(output)}
        let value=UInt(bitPattern:process)
        watcher=Thread {
            guard let process=HANDLE(bitPattern:value) else {Self.finish(output)}
            _=WaitForSingleObject(process,INFINITE);_ = CloseHandle(process);Self.finish(output)
        }
        watcher.name="SpaceSniffer.ParentLifetime";watcher.start()
#else
        guard kill(pid_t(pid),0)==0 else {Self.finish(output)}
        watcher=DispatchSource.makeProcessSource(identifier:pid_t(pid),eventMask:.exit,queue:.global(qos:.utility))
        watcher.setEventHandler {Self.finish(output)};watcher.resume()
        if kill(pid_t(pid),0) != 0 {Self.finish(output)}
#endif
    }
    private static func ownedOutput(_ args:[String],parent:UInt32)->URL? {
        guard let index=args.firstIndex(of:"--output"),args.indices.contains(index+1) else {return nil}
        let directory=URL(fileURLWithPath:args[index+1]).deletingLastPathComponent().resolvingSymlinksInPath()
        let base=FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        guard directory.deletingLastPathComponent().standardizedFileURL==base.standardizedFileURL,
              directory.lastPathComponent.hasPrefix("sniffer-gpui-\(parent)-") else {return nil}
        return directory
    }
    private static func finish(_ output:URL?)->Never {if let output {try? FileManager.default.removeItem(at:output)};exit(0)}
}
