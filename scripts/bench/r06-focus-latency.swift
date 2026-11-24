import Foundation
import Darwin
import SpaceSnifferCore

@main enum FocusLatencyProbe {
    static func settled(_ subscription: ScanSubscription, after revision: UInt64?) async throws -> ScanUpdate {
        for await update in subscription.updates {
            if !update.isScanning && (revision == nil || update.revision > revision!) { return update }
        }
        throw CocoaError(.userCancelled)
    }
    static func main() async throws {
        let root=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("sniffer-r06-profile-"+UUID().uuidString)
        let branch=root.appendingPathComponent("branch"); try FileManager.default.createDirectory(at:branch,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        for i in 0..<256 { try Data(repeating:UInt8(i%255),count:i%17).write(to:branch.appendingPathComponent("file-\(i).bin")) }
        let admission=ScanAdmission(limit:1); let service=ScanService(admission:admission)
        let subscription=await service.subscribe(root,watching:false)
        var snapshot=try await settled(subscription,after:nil); let frozen=snapshot.snapshot
        let scope=subscription.rootPath+"/branch"; var rows:[[String:Any]]=[]
        for pair in 0..<10 {
            for mode in (pair%2==0 ? ["legacy-scope","focus-intent"]:["focus-intent","legacy-scope"]) {
                let revision=snapshot.revision; let start=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                if mode=="legacy-scope" { await service.rescan(rootPath:subscription.rootPath,scope:scope) }
                else { let request=await service.requestFocusRescan(subscription:subscription,scope:scope); precondition(request != nil) }
                snapshot=try await settled(subscription,after:revision)
                let seconds=Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-start)/1e9
                precondition(snapshot.snapshot.fileCount==256 && snapshot.snapshot.nodes[0].logicalBytes==frozen.nodes[0].logicalBytes)
                rows.append(["pair":pair,"mode":mode,"seconds":seconds,"files":snapshot.snapshot.fileCount,"logical":snapshot.snapshot.nodes[0].logicalBytes])
            }
        }
        await service.unsubscribe(subscription.id,rootPath:subscription.rootPath); admission.shutdown()
        let report:[String:Any]=["scope":"idle serialized actual ScanService, owned fixture256files, 10 alternating pairs in one process; debug Core linked to optimized probe. UI watcher inactive. Other GUI/host work concurrent. No blocked-master/user latency or parallel speed claim. No auto-enable.","rows":rows,"frozen_reader_unchanged":frozen.nodes[0].logicalBytes==snapshot.snapshot.nodes[0].logicalBytes]
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
    }
}
