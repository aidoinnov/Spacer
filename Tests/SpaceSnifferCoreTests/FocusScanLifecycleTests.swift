import XCTest
@testable import SpaceSnifferCore

final class FocusScanLifecycleTests: XCTestCase, @unchecked Sendable {
    private enum WaitError: Error { case timeout, ended }
    private func wait(_ subscription: ScanSubscription, where predicate: @escaping @Sendable (ScanUpdate) -> Bool) async throws -> ScanUpdate {
        try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask { for await value in subscription.updates where predicate(value) { return value }; throw WaitError.ended }
            group.addTask { try await Task.sleep(for: .seconds(8)); throw WaitError.timeout }
            defer { group.cancelAll() }; return try await group.next()!
        }
    }
    private func fixture() throws -> URL {
        let root=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("sniffer-focus-"+UUID().uuidString)
        for path in ["a/child","b"] { try FileManager.default.createDirectory(at:root.appendingPathComponent(path),withIntermediateDirectories:true) }
        try Data([1]).write(to:root.appendingPathComponent("a/child/data.bin"))
        try Data([2]).write(to:root.appendingPathComponent("b/data.bin"))
        return root.standardizedFileURL.resolvingSymlinksInPath()
    }
    private func fields(_ snapshot: ScanSnapshot) -> [String: Int64] {
        Dictionary(uniqueKeysWithValues:snapshot.nodes.map { ($0.path,$0.logicalBytes) })
    }
    func testMasterIsNotCancelledAndOwnersMergeFromLatestSerializedBaseline() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"master gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false)
        let original=try await wait(a) { !$0.isScanning }
        let b=await service.subscribe(root,watching:false)
        await service.rescan(rootPath:a.rootPath); await fulfillment(of:[started],timeout:3)
        let obsolete=await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        let other=await service.requestFocusRescan(subscription:b,scope:root.appendingPathComponent("a/child").path)
        let latest=await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("b").path)
        XCTAssertNotNil(obsolete); XCTAssertNotNil(other); XCTAssertNotNil(latest)
        await service.cancelFocusRescan(try XCTUnwrap(obsolete)) // Old receipt cannot cancel latest.
        XCTAssertFalse(probe.blockedControlIsCancelled); XCTAssertEqual(probe.paths.count,2)
        try Data([3,4,5]).write(to:root.appendingPathComponent("a/child/data.bin"))
        try Data([6,7]).write(to:root.appendingPathComponent("b/data.bin"))
        gate.signal()
        let final=try await wait(a) { !$0.isScanning && $0.scope == root.appendingPathComponent("a/child").path && $0.snapshot.nodes.first?.logicalBytes == 5 }
        XCTAssertEqual(fields(final.snapshot),fields(DiskScanner.scan(root)))
        XCTAssertEqual(original.snapshot.nodes[0].logicalBytes,2) // Frozen reader unchanged.
        XCTAssertEqual(probe.paths,[root.path,root.path,root.appendingPathComponent("b").path,root.appendingPathComponent("a/child").path])
        XCTAssertEqual(probe.peakActive,1)
        await service.unsubscribe(a.id,rootPath:a.rootPath); await service.unsubscribe(b.id,rootPath:b.rootPath)
    }
    func testRunningOwnerReplacementSuppressesPartialAndObsoleteTerminalButKeepsOtherOwner() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"root focus gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate,emitPartial:true)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false); let baseline=try await wait(a) { !$0.isScanning }
        let b=await service.subscribe(root,watching:false)
        let oldReceipt=await service.requestFocusRescan(subscription:a,scope:root.path)
        let old=try XCTUnwrap(oldReceipt)
        await fulfillment(of:[started],timeout:3)
        let observer=await service.subscribe(root,watching:false)
        let during=try await wait(observer) { $0.isScanning }
        XCTAssertEqual(Array(during.snapshot.nodes),Array(baseline.snapshot.nodes)) // Root-only progress was not published.
        _ = await service.requestFocusRescan(subscription:b,scope:root.appendingPathComponent("a").path)
        _ = await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a/child").path)
        XCTAssertTrue(probe.blockedControlIsCancelled)
        await service.cancelFocusRescan(old)
        try Data([1,2,3,4]).write(to:root.appendingPathComponent("a/child/data.bin"))
        await service.setTag(2,path:root.appendingPathComponent("b/data.bin").path,rootPath:a.rootPath)
        gate.signal()
        let final=try await wait(a) { !$0.isScanning && $0.scope == root.appendingPathComponent("a/child").path && $0.snapshot.nodes.first?.logicalBytes == 5 }
        XCTAssertEqual(fields(final.snapshot),fields(DiskScanner.scan(root)))
        XCTAssertEqual(final.snapshot.tags[root.appendingPathComponent("b/data.bin").path],2)
        XCTAssertEqual(probe.paths,[root.path,root.path,root.appendingPathComponent("a").path,root.appendingPathComponent("a/child").path])
        XCTAssertEqual(probe.peakActive,1)
        await service.unsubscribe(a.id,rootPath:a.rootPath); await service.unsubscribe(b.id,rootPath:b.rootPath)
        await service.unsubscribe(observer.id,rootPath:observer.rootPath)
    }
    func testUnsubscribeAndExplicitMasterResetRemoveOwnerIntentsWithoutCancellingMaster() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"master gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false); _ = try await wait(a) { !$0.isScanning }
        let b=await service.subscribe(root,watching:false)
        await service.rescan(rootPath:a.rootPath); await fulfillment(of:[started],timeout:3)
        _ = await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        _ = await service.requestFocusRescan(subscription:b,scope:root.appendingPathComponent("b").path)
        await service.unsubscribe(b.id,rootPath:b.rootPath)
        XCTAssertFalse(probe.blockedControlIsCancelled)
        await service.rescan(rootPath:a.rootPath) // Explicit master supersedes all remaining intents.
        XCTAssertTrue(probe.blockedControlIsCancelled); gate.signal()
        _ = try await wait(a) { !$0.isScanning && !$0.snapshot.cancelled }
        XCTAssertEqual(probe.paths,[root.path,root.path,root.path])
        await service.unsubscribe(a.id,rootPath:a.rootPath)
    }
    func testUnsubscribingRunningFocusOwnerDrainsItBeforeOtherOwner() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"focus gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false); _ = try await wait(a) { !$0.isScanning }
        let b=await service.subscribe(root,watching:false)
        _ = await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        await fulfillment(of:[started],timeout:3)
        _ = await service.requestFocusRescan(subscription:b,scope:root.appendingPathComponent("b").path)
        await service.unsubscribe(a.id,rootPath:a.rootPath)
        XCTAssertTrue(probe.blockedControlIsCancelled)
        try Data([1,2,3]).write(to:root.appendingPathComponent("b/data.bin"))
        gate.signal()
        let final=try await wait(b) { !$0.isScanning && $0.scope == root.appendingPathComponent("b").path }
        XCTAssertEqual(final.snapshot.nodes[0].logicalBytes,4)
        XCTAssertEqual(probe.paths,[root.path,root.appendingPathComponent("a").path,root.appendingPathComponent("b").path])
        XCTAssertEqual(probe.peakActive,1)
        await service.unsubscribe(b.id,rootPath:b.rootPath)
    }
    func testQueuedReplacementToOutsideSymlinkIsRejectedBeforeScannerIO() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let outside=try fixture(); defer { try? FileManager.default.removeItem(at:outside) }
        let started=expectation(description:"master gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false); let baseline=try await wait(a) { !$0.isScanning }
        await service.rescan(rootPath:a.rootPath); await fulfillment(of:[started],timeout:3)
        _ = await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        try FileManager.default.removeItem(at:root.appendingPathComponent("a"))
        try FileManager.default.createSymbolicLink(atPath:root.appendingPathComponent("a").path,withDestinationPath:outside.path)
        gate.signal()
        let final=try await wait(a) { !$0.isScanning && $0.scope == root.appendingPathComponent("a").path }
        XCTAssertEqual(fields(final.snapshot),fields(baseline.snapshot))
        XCTAssertEqual(probe.paths,[root.path,root.path]) // Only the master calls entered the injected scanner.
        await service.unsubscribe(a.id,rootPath:a.rootPath)
    }
    func testTargetReplacementDuringFocusCannotCommitOldCandidate() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"focus result gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false); let baseline=try await wait(a) { !$0.isScanning }
        try Data([1,2,3,4]).write(to:root.appendingPathComponent("a/child/data.bin"))
        _ = await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        await fulfillment(of:[started],timeout:3)
        try FileManager.default.moveItem(at:root.appendingPathComponent("a"),to:root.appendingPathComponent("a-old"))
        try FileManager.default.createDirectory(at:root.appendingPathComponent("a"),withIntermediateDirectories:true)
        gate.signal()
        let final=try await wait(a) { !$0.isScanning }
        XCTAssertEqual(fields(final.snapshot),fields(baseline.snapshot))
        XCTAssertEqual(final.revision,baseline.revision) // Rejected focus does not manufacture a tree revision.
        await service.unsubscribe(a.id,rootPath:a.rootPath)
    }
    func testRemovedRootIncarnationCannotPublishOrCancelFreshFocus() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"old focus gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let old=await service.subscribe(root,watching:false); _ = try await wait(old) { !$0.isScanning }
        let oldReceipt=await service.requestFocusRescan(subscription:old,scope:root.appendingPathComponent("a").path)
        let ticket=try XCTUnwrap(oldReceipt); await fulfillment(of:[started],timeout:3)
        await service.unsubscribe(old.id,rootPath:old.rootPath)
        try Data([1,2,3,4]).write(to:root.appendingPathComponent("b/data.bin"))
        let fresh=await service.subscribe(root,watching:false); let baseline=try await wait(fresh) { !$0.isScanning }
        let newReceipt=await service.requestFocusRescan(subscription:fresh,scope:root.appendingPathComponent("b").path)
        let current=try XCTUnwrap(newReceipt)
        XCTAssertNotEqual(ticket.rootIncarnation,current.rootIncarnation)
        await service.cancelFocusRescan(ticket)
        _ = try await wait(fresh) { !$0.isScanning && $0.scope == root.appendingPathComponent("b").path }
        gate.signal()
        // Allow the cancelled old admission completion to enqueue; current
        // publication must retain the fresh incarnation.
        try await Task.sleep(for:.milliseconds(30))
        let reader=await service.subscribe(root,watching:false); let final=try await wait(reader) { !$0.isScanning }
        XCTAssertEqual(fields(final.snapshot),fields(baseline.snapshot))
        await service.unsubscribe(fresh.id,rootPath:fresh.rootPath); await service.unsubscribe(reader.id,rootPath:reader.rootPath)
    }
    func testStopResetsPendingFocusWithoutRestartingOrDroppingBaseline() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"focus gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false); let baseline=try await wait(a) { !$0.isScanning }
        let b=await service.subscribe(root,watching:false)
        _ = await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        await fulfillment(of:[started],timeout:3)
        _ = await service.requestFocusRescan(subscription:b,scope:root.appendingPathComponent("b").path)
        await service.stop(rootPath:a.rootPath); XCTAssertTrue(probe.blockedControlIsCancelled)
        gate.signal(); let stopped=try await wait(a) { !$0.isScanning }
        XCTAssertEqual(fields(stopped.snapshot),fields(baseline.snapshot))
        XCTAssertEqual(probe.paths,[root.path,root.appendingPathComponent("a").path])
        await service.unsubscribe(a.id,rootPath:a.rootPath); await service.unsubscribe(b.id,rootPath:b.rootPath)
    }
    func testQueuedFocusDoesNotConsumeWatchOverflowAndFinalRootConverges() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"first focus gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate); let monitor=FocusMonitorDelivery()
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run,monitorFactory:{ _,callback in monitor.set(callback); return NSObject() })
        let a=await service.subscribe(root,watching:true); _ = try await wait(a) { !$0.isScanning }
        let b=await service.subscribe(root,watching:false)
        _ = await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        await fulfillment(of:[started],timeout:3)
        _ = await service.requestFocusRescan(subscription:b,scope:root.path)
        try Data([1,2,3,4,5]).write(to:root.appendingPathComponent("a/child/data.bin"))
        await monitor.send([PathChange(path:root.path,isDirectory:true,mustRescan:true)])
        let pending=await service.pendingQueueObservation(rootPath:a.rootPath); XCTAssertEqual(pending?.count,1)
        gate.signal()
        let final=try await wait(a) { !$0.isScanning && probe.paths.count == 4 }
        XCTAssertEqual(fields(final.snapshot),fields(DiskScanner.scan(root)))
        XCTAssertEqual(probe.paths,[root.path,root.appendingPathComponent("a").path,root.path,root.path])
        await service.unsubscribe(a.id,rootPath:a.rootPath); await service.unsubscribe(b.id,rootPath:b.rootPath)
    }
    func testCancelledOwnerAndRejectedScopesDoNotStartIO() async throws {
        let root=try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        let started=expectation(description:"master gated"); let gate=DispatchSemaphore(value:0); defer { gate.signal() }
        let probe=FocusScannerProbe(blockCall:2,started:started,gate:gate)
        let admission=ScanAdmission(limit:4); defer { admission.shutdown() }
        let service=ScanService(admission:admission,scanner:probe.run)
        let a=await service.subscribe(root,watching:false); _ = try await wait(a) { !$0.isScanning }
        let outside=await service.requestFocusRescan(subscription:a,scope:"/private/tmp")
        let file=await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("b/data.bin").path)
        let missing=await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("missing").path)
        XCTAssertNil(outside); XCTAssertNil(file); XCTAssertNil(missing)
        await service.rescan(rootPath:a.rootPath); await fulfillment(of:[started],timeout:3)
        let receipt=await service.requestFocusRescan(subscription:a,scope:root.appendingPathComponent("a").path)
        let ticket=try XCTUnwrap(receipt)
        await service.cancelFocusRescan(ticket); XCTAssertFalse(probe.blockedControlIsCancelled)
        gate.signal(); _ = try await wait(a) { !$0.isScanning }
        XCTAssertEqual(probe.paths,[root.path,root.path])
        await service.unsubscribe(a.id,rootPath:a.rootPath)
    }
}

private final class FocusScannerProbe: @unchecked Sendable {
    private let lock=NSLock(); private var calls:[String]=[]; private var active=0; private var peak=0
    private var blockedControl:ScanControl?
    let blockCall:Int, started:XCTestExpectation, gate:DispatchSemaphore, emitPartial:Bool
    init(blockCall:Int,started:XCTestExpectation,gate:DispatchSemaphore,emitPartial:Bool=false) {
        self.blockCall=blockCall; self.started=started; self.gate=gate; self.emitPartial=emitPartial
    }
    var paths:[String] { lock.withLock { calls } }
    var peakActive:Int { lock.withLock { peak } }
    var blockedControlIsCancelled:Bool { lock.withLock { blockedControl?.isCancelled ?? false } }
    func run(_ url:URL,_ control:ScanControl,_ progress:(@Sendable(ScanSnapshot)->Void)?,_ heartbeat:(@Sendable(ScanProgress)->Void)?) -> ScanSnapshot {
        let number=lock.withLock { calls.append(url.path); active+=1; peak=max(peak,active); return calls.count }
        defer { lock.withLock { active-=1 } }
        let result=DiskScanner.scan(url) // Deliberately ignores cancellation to exercise publication guard.
        if number==blockCall {
            lock.withLock { blockedControl=control }
            if emitPartial, let root=result.nodes.first {
                var partial=result; var node=root; node.children=[]; partial.nodes=NodeTable([node]); partial.fileCount=0; partial.folderCount=1
                progress?(partial)
            }
            started.fulfill(); _ = gate.wait(timeout:.now()+6)
        }
        return result
    }
}

private final class FocusMonitorDelivery: @unchecked Sendable {
    private let lock=NSLock(); private var callback:ScanService.MonitorDelivery?
    func set(_ value:@escaping ScanService.MonitorDelivery) { lock.withLock { callback=value } }
    func send(_ changes:[PathChange]) async { if let callback=lock.withLock({ callback }) { await callback(changes) } }
}
