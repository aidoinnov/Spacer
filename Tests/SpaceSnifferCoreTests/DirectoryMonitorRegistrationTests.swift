import XCTest
@testable import SpaceSnifferCore

final class DirectoryMonitorRegistrationTests: XCTestCase {
    private final class Released: @unchecked Sendable {
        let action:@Sendable()->Void
        init(_ action:@escaping @Sendable()->Void) {self.action=action}
        deinit {action()}
    }
    func testBlockedRegistrationDoesNotBlockScanOrServiceCancellation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        try Data([1,2,3]).write(to:root.appendingPathComponent("f"))
        let entered=expectation(description:"registration entered"), released=expectation(description:"cancelled native object released")
        let gate=DispatchSemaphore(value:0); defer {gate.signal()}
        let admission=ScanAdmission(limit:1); defer {admission.shutdown()}
        let service=ScanService(admission:admission,scanner:{url,control,progress,heartbeat in
            DiskScanner.scan(url,control:control,progress:progress,heartbeat:heartbeat)
        },monitorFactory:{_,_ in
            DirectoryMonitorRegistration(create:{
                entered.fulfill(); gate.wait(); return Released {released.fulfill()}
            },ready:{XCTFail("cancelled registration became active")})
        })
        let subscription=await service.subscribe(root,watching:true)
        await fulfillment(of:[entered],timeout:2)
        let finished=expectation(description:"scan completes while registration blocked")
        let consumer=Task {
            for await update in subscription.updates where !update.isScanning {
                XCTAssertEqual(update.snapshot.nodes[0].logicalBytes,3)
                XCTAssertFalse(update.watchActive);finished.fulfill();break
            }
        }
        await fulfillment(of:[finished],timeout:2)
        await service.unsubscribe(subscription.id,rootPath:subscription.rootPath)
        let stats=await service.statistics();XCTAssertEqual(stats.roots,0)
        gate.signal();await fulfillment(of:[released],timeout:2);consumer.cancel()
    }
    func testReadinessIsPublishedAfterNativeCreationAndOwnerIsReleased() async {
        let ready=expectation(description:"watch ready"), released=expectation(description:"native released")
        var owner:DirectoryMonitorRegistration?=DirectoryMonitorRegistration(create:{Released {released.fulfill()}},ready:{ready.fulfill()})
        await fulfillment(of:[ready],timeout:2);XCTAssertTrue(owner?.watchActive == true)
        owner=nil
        await fulfillment(of:[released],timeout:2)
    }
}

extension DirectoryMonitorRegistrationTests {
    func testJournalCursorCoversMutationBeforeWatchRegistrationCompletes() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("f");try Data([1,2,3]).write(to:file)
        let entered=expectation(description:"registration deferred"),gate=DispatchSemaphore(value:0)
        defer {gate.signal()}
        let admission=ScanAdmission(limit:1);defer {admission.shutdown()}
        let service=ScanService(admission:admission,scanner:{url,control,progress,heartbeat in
            DiskScanner.scan(url,control:control,progress:progress,heartbeat:heartbeat)
        },monitorFactory:{path,deliver in
            let cursor=DirectoryMonitor.eventCursor()
            return DirectoryMonitorRegistration(create:{
                entered.fulfill();gate.wait()
                return DirectoryMonitor(path:path,since:cursor ?? DirectoryMonitor.nowCursor) {changes in Task {await deliver(changes)}}
            },ready:{Task {await deliver(cursor == nil ? [PathChange(path:path,isDirectory:true,mustRescan:true)] : [])}})
        })
        let subscription=await service.subscribe(root,watching:true)
        await fulfillment(of:[entered],timeout:2)
        let initial=expectation(description:"initial result before monitor ready")
        let changed=expectation(description:"registration gap mutation recovered")
        let consumer=Task {
            var initialSent=false
            for await update in subscription.updates where !update.isScanning {
                if !initialSent {initialSent=true;XCTAssertEqual(update.snapshot.nodes[0].logicalBytes,3);initial.fulfill()}
                if update.watchActive && update.snapshot.nodes[0].logicalBytes == 7 {changed.fulfill();break}
            }
        }
        await fulfillment(of:[initial],timeout:2)
        try Data(repeating:9,count:7).write(to:file)
        gate.signal();await fulfillment(of:[changed],timeout:5)
        await service.unsubscribe(subscription.id,rootPath:subscription.rootPath);consumer.cancel()
    }
}
