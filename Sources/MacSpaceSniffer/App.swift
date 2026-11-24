import SwiftUI
import AppKit
import SpaceSnifferCore
import SpaceSnifferAutomation

@main
struct MacSpaceSnifferApp: App {
    init() { HeadlessCommand.runIfRequested() }
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Mac Space Sniffer") { ContentView() }
            .defaultSize(width: 1340, height: 860)
            .windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unifiedCompact)
            .commands { SnifferCommands() }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: LocalControlServer?
    func applicationWillTerminate(_ notification: Notification) { AutomationHub.shared.releaseHiddenWindows(); controller?.stop() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        do {
            controller = try LocalControlServer(bundleID: Bundle.main.bundleIdentifier ?? "local.macspacesniffer.app") { request in
                await AutomationHub.shared.handle(request)
            }
        } catch { NSLog("Local control unavailable: %@", error.localizedDescription) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !AutomationHub.shared.hasExplicitlyHiddenWindows }
}
struct StoreKey: FocusedValueKey { typealias Value = ScanStore }
extension FocusedValues { var scanStore: ScanStore? { get { self[StoreKey.self] } set { self[StoreKey.self] = newValue } } }
struct SnifferCommands: Commands {
    @FocusedValue(\.scanStore) var store
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("폴더 스캔…") { store?.chooseFolder() }.keyboardShortcut("o")
            Button("스냅샷 열기…") { store?.loadSnapshot() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("스냅샷 저장…") { store?.saveSnapshot() }.keyboardShortcut("s").disabled(store?.snapshot == nil)
            Button("파일 목록 내보내기…") { store?.exportFileList() }.keyboardShortcut("e").disabled(store?.snapshot == nil)
        }
        CommandMenu("탐색") {
            Button("뒤로") { store?.back() }.keyboardShortcut("[").disabled(store?.canBack != true)
            Button("앞으로") { store?.forward() }.keyboardShortcut("]").disabled(store?.canForward != true)
            Button("상위 폴더") { store?.up() }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("스캔 시작 위치") { store?.navigate(0) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("다시 스캔") { store?.rescan() }.keyboardShortcut("r").disabled(store?.offline != false || store?.isScanning != false)
            Button("현재 폴더 다시 스캔") { store?.rescanFocus() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(store?.offline != false || store?.isScanning != false)
            Button("스캔 중지") { store?.stop() }.keyboardShortcut(".").disabled(store?.isScanning != true)
            Button("Finder에서 보기") { if let store { store.reveal(store.selected ?? store.focus) } }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(store?.offline != false)
        }
        CommandGroup(replacing: .help) {
            Button("사용 방법") {
                let alert = NSAlert(); alert.messageText = "Mac Space Sniffer 사용 방법"
                alert.informativeText = "폴더를 선택하거나 창에 드래그해 스캔하세요.\n\n클릭: 선택 · 클릭: 내부 상세화 · 더블 클릭: 폴더 확대\n우클릭: Finder 표시, 색상 태그, 휴지통 이동\n방향키: 항목 선택 · Return: 열기 · ⌘[: 뒤로\n\n필터 예시\n*.zip;*.dmg — 이름 조건 OR\n*.zip;>100mb — 조건 AND\n|*.tmp — 제외\n>30d — 수정된 지 30일 초과\n:tag:red — 빨강 태그\n\\node_modules — 경로에 포함된 폴더\n\n권한이 없는 폴더는 건너뛰고 기록합니다. 필요하면 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한에서 이 앱을 허용한 뒤 다시 스캔하세요."
                alert.runModal()
            }
        }
    }
}
