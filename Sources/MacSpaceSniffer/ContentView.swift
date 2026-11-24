import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SpaceSnifferCore

private let page = Color(red: 0.055, green: 0.075, blue: 0.095)
private let panel = Color(red: 0.085, green: 0.105, blue: 0.125)
private let accent = Color(red: 0.43, green: 0.83, blue: 0.70)

struct ContentView: View {
    @StateObject private var store = ScanStore()
    @State private var filterHelp = false
    @State private var dropTarget = false
    @State private var openedArgument = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 208)
                Divider()
                VStack(spacing: 0) {
                    if store.snapshot == nil && !store.isScanning { welcome }
                    else { workspace }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.snapshot != nil {
                    Divider()
                    inspector.frame(width: 250)
                }
            }
            Divider()
            statusbar
        }
        .background(page)
        .foregroundStyle(Color.white.opacity(0.88))
        .preferredColorScheme(.dark)
        .tint(accent)
        .frame(minWidth: 1040, minHeight: 680)
        .toolbar {
            ToolbarItem(placement: .navigation) { toolbarBrand }
            ToolbarItem(placement: .automatic) { Spacer() }
            ToolbarItem(placement: .primaryAction) { toolbarActions }
        }
        .toolbarBackground(panel, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .background(AutomationWindowAttachment(store: store).frame(width: 0, height: 0))
        .focusedSceneValue(\.scanStore, store)
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 12).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(5).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.pathExtension.lowercased() == "sns" { store.loadSnapshot(url) }
                    else {
                        var directory: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue { store.start(url) }
                        else { store.notice = "폴더 또는 SNS 스냅샷을 드래그하세요." }
                    }
                }
            }
            return true
        }
        .onAppear {
            store.loadVolumes()
            guard !openedArgument else { return }; openedArgument = true
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--include-mounted-volumes") { store.setVolumeTraversal(.allVolumes) }
            if let index = args.firstIndex(of: "--scan"), args.indices.contains(index + 1) { store.start(URL(fileURLWithPath: args[index + 1])) }
            else if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) { store.loadSnapshot(URL(fileURLWithPath: args[index + 1])) }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in store.loadVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in store.loadVolumes() }
        // View disappearance also occurs for ordered-out windows. Native
        // willClose observers own unregister/shutdown; hiding keeps data live.
        .sheet(isPresented: $store.showIssues) { issuesSheet }
    }
    private var toolbarBrand: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill").font(.title3).foregroundStyle(accent)
            Text("Mac Space Sniffer").font(.system(size: 14, weight: .semibold))
            Text("DISK EXPLORER").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(.secondary)
        }.lineLimit(1)
    }
    private var toolbarActions: some View {
        HStack(spacing: 12) {
            if store.isScanning {
                ProgressView().controlSize(.small).scaleEffect(0.65).frame(width: 16)
                Text("디스크 읽는 중").font(.system(size: 11)).foregroundStyle(accent)
            } else if store.offline {
                Label("스냅샷", systemImage: "camera").font(.system(size: 11)).foregroundStyle(.orange)
            }
            Button { store.chooseFolder() } label: { Label("폴더 스캔", systemImage: "folder.badge.plus").padding(.horizontal, 5) }
                .buttonStyle(.borderedProminent).controlSize(.small).foregroundStyle(page).keyboardShortcut("o")
            Menu {
                Button("스냅샷 열기…", action: store.loadSnapshot)
                Button("스냅샷 저장…", action: store.saveSnapshot).disabled(store.snapshot == nil)
                Button("파일 목록 내보내기…", action: store.exportFileList).disabled(store.snapshot == nil)
                Divider()
                Toggle("숨김 파일 표시", isOn: $store.showHidden)
                Toggle("파일 유형별 색상", isOn: $store.colorByType)
                Toggle("파일 변경 시 자동 재스캔", isOn: $store.liveUpdates)
                Toggle("다른 볼륨까지 포함", isOn: Binding(get: { store.volumeTraversal == .allVolumes }, set: { store.setVolumeTraversal($0 ? .allVolumes : .selectedVolume) }))
                    .help("변경하면 현재 폴더를 새 범위로 다시 검사합니다.")
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).frame(width: 25)
        }.labelStyle(.titleAndIcon).lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("즐겨찾기").padding(.top, 24).padding(.bottom, 10)
            location("홈 폴더", "house", FileManager.default.homeDirectoryForCurrentUser)
            location("다운로드", "arrow.down.circle", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
            location("데스크탑", "desktopcomputer", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
            location("응용 프로그램", "app.dashed", URL(fileURLWithPath: "/Applications"))
            sectionLabel("볼륨").padding(.top, 29).padding(.bottom, 10)
            ForEach(store.volumes) { volume in
                location(volume.name, "internaldrive", volume.url)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Label("사용량을 한눈에", systemImage: "square.grid.3x3").font(.system(size: 12, weight: .medium))
                Text("큰 영역부터 살펴보세요.\n폴더를 더블 클릭하면\n안쪽을 자세히 볼 수 있어요.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
                Button("스냅샷 열기…", action: store.loadSnapshot).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8)).padding(14)
        }.background(panel.opacity(0.65))
    }
    private func location(_ name: String, _ icon: String, _ url: URL) -> some View {
        Button { store.start(url) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(store.snapshot?.rootPath == url.path ? accent : .white.opacity(0.45))
                Text(name).lineLimit(1).font(.system(size: 12))
                Spacer(minLength: 0)
                if store.snapshot?.rootPath == url.path { Circle().fill(accent).frame(width: 5, height: 5) }
            }.padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
                .background(store.snapshot?.rootPath == url.path ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).padding(.horizontal, 9).help(url.path)
    }
    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).padding(.horizontal, 22)
    }
    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(accent.opacity(0.045)).frame(width: 112, height: 112)
                Image(systemName: "square.grid.2x2").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(accent)
            }.padding(.bottom, 28)
            Text("디스크 공간, 어디에 쓰이고 있나요?").font(.system(size: 27, weight: .medium))
            Text("폴더를 스캔하면 파일과 폴더의 크기를 지도로 보여드립니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 13)
            Button("폴더를 선택해서 시작", action: store.chooseFolder).buttonStyle(.borderedProminent)
                .controlSize(.large).foregroundStyle(page).padding(.top, 28)
            Text("또는 이 창에 폴더를 드래그하세요").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 13)
            HStack(spacing: 35) {
                feature("square.grid.3x3", "크기에 비례하는 트리맵")
                feature("line.3.horizontal.decrease", "이름·크기·기간 필터")
                feature("tag", "태그와 보고서")
            }.padding(.top, 65)
            Spacer()
            Text("macOS 네이티브 · 로컬에서 분석 · macOS 14+").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.25)).padding(.bottom, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func feature(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.white.opacity(0.5)); Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                tool("chevron.left", "뒤로", disabled: !store.canBack, action: store.back)
                tool("chevron.right", "앞으로", disabled: !store.canForward, action: store.forward)
                Button(action: store.up) {
                    Label("상위 폴더", systemImage: "arrow.up").font(.system(size: 11))
                }.buttonStyle(.bordered).controlSize(.small).disabled(store.focus == 0)
                    .help(store.focus == 0 ? "스캔 시작 위치입니다. 다른 위치는 폴더 스캔으로 선택하세요." : "상위 폴더로 이동 (⌘↑)")
                Divider().frame(height: 16).padding(.horizontal, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.breadcrumb) { node in
                            if node.id != 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary) }
                            Button(node.name) { store.navigate(node.id) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(node.id == store.focus ? .white : .white.opacity(0.45))
                        }
                    }
                }
                Spacer(minLength: 3)
                if store.isScanning { tool("stop.fill", "스캔 중지", action: store.stop) }
                else { tool("arrow.clockwise", "다시 스캔", disabled: store.offline, action: store.rescan) }
            }.padding(.horizontal, 18).frame(height: 47)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(store.focusedNode?.name ?? "분석 중").font(.system(size: 25, weight: .medium)).lineLimit(1)
                Spacer()
                Text(formattedBytes(store.displayedBytes)).font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit()
                Text(store.sizeMode == .allocated ? "디스크 사용량" : "파일 크기").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 13).padding(.bottom, 20)
            filterBar
            if store.isScanning {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("스캔 진행 중 · 표시 용량은 현재까지 집계한 값입니다")
                        Spacer()
                        if let progress = store.scanProgress {
                            Text("폴더 검사 \(progress.visitedFolders.formatted()) · 대기 \(progress.pendingFolders.formatted())")
                        }
                    }
                    if let progress = store.scanProgress {
                        Text(progress.currentPath).lineLimit(1).truncationMode(.middle).help(progress.currentPath)
                        if progress.issueCount > 0 { Text("접근 오류 \(progress.issueCount.formatted())개 · 읽을 수 있는 항목은 계속 검사합니다").foregroundStyle(.orange) }
                    }
                }.font(.system(size: 10)).foregroundStyle(accent).padding(.horizontal, 20).padding(.bottom, 8)
                if let overview = store.scanProgress?.overview,
                   !overview.folders.isEmpty || !overview.largeFiles.isEmpty {
                    let paintSession = store.automationScanSessionID
                    VStack(alignment: .leading, spacing: 7) {
                        Text("빠른 개요 · 최근 집계한 디스크 사용량").font(.system(size: 11, weight: .medium)).help(store.scanProgress?.rootPath ?? "")
                        HStack(alignment: .top, spacing: 24) {
                            overviewColumn("큰 폴더", items: overview.folders)
                            overviewColumn("큰 파일", items: overview.largeFiles)
                        }
                        Text("미확인 영역은 계속 분석 중입니다").font(.system(size: 9)).foregroundStyle(.secondary)
                    }.padding(12).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .background(OverviewPaintProbe { store.markOverviewPainted(session: paintSession) })
                        .padding(.horizontal, 20).padding(.bottom, 8)
                }
            }
            if let error = store.filterError { inlineMessage(error, color: .orange) }
            if let notice = store.notice {
                HStack { Text(notice).font(.system(size: 11)); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    .foregroundStyle(.orange.opacity(0.85)).padding(10).background(.orange.opacity(0.06))
            }
            if store.listMode { fileList }
            else {
                ZStack {
                    TreemapView(store: store)
                    if !store.isScanning && store.snapshot?.nodes.isEmpty == false && store.displayedBytes == 0 {
                        VStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal.decrease.circle").font(.largeTitle).foregroundStyle(.secondary)
                            Text("표시할 사용량이 없습니다").font(.system(size: 14))
                            Text("필터, 크기 기준, 숨김 파일 설정을 확인하세요.").font(.system(size: 11)).foregroundStyle(.secondary)
                            if !store.filterText.isEmpty { Button("필터 지우기", action: store.clearFilter).buttonStyle(.bordered) }
                        }.padding(24).background(page.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 13) {
                ForEach(FileCategory.allCases.filter { $0 != .folder }, id: \.self) { type in
                    HStack(spacing: 4) { Circle().fill(type.color).frame(width: 5, height: 5); Text(type.title).font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Text("더블 클릭: 확대 · 우클릭: 작업").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 18).frame(height: 30)
        }
    }
    private func overviewColumn(_ title: String, items: [ScanOverviewItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            ForEach(items.prefix(4)) { item in
                HStack {
                    Text(item.name).lineLimit(1).truncationMode(.middle).help(item.path)
                    Spacer(minLength: 8)
                    Text(formattedBytes(item.allocatedBytes)).monospacedDigit()
                }.font(.system(size: 10))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(accent).font(.system(size: 12))
            TextField("필터: *.zip;>100mb 또는 >30d", text: $store.filterText).textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).onSubmit(store.applyFilter)
            if !store.filterText.isEmpty { Button(action: store.clearFilter) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            Button("적용", action: store.applyFilter).controlSize(.mini).buttonStyle(.bordered)
            Button { filterHelp.toggle() } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.plain).foregroundStyle(.secondary)
                .popover(isPresented: $filterHelp) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("빠른 필터").font(.headline)
                        Text("*.zip;*.dmg    파일명 OR\n*.zip;>100mb    크기 조건 결합\n|*.tmp         제외\n>30d           수정 후 30일 초과\n:tag:red       빨강 태그\n\\node_modules 경로의 폴더 이름\n:class:Video/Movies 동영상 클래스\nlogicalsize>1gb 논리 크기 기준").font(.system(size: 11, design: .monospaced)).lineSpacing(4)
                        Text("크기 단위는 1 KB = 1,024 B입니다.\n입력 후 Return 또는 적용을 누르세요.").font(.caption).foregroundStyle(.secondary)
                    }.padding(20)
                }
            Divider().frame(height: 16)
            Menu {
                Picker("표시 깊이", selection: $store.depth) { ForEach(1...6, id: \.self) { Text("\($0)단계").tag($0) } }
                Picker("크기 기준", selection: $store.sizeMode) { ForEach(SizeMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("숨김 파일 표시", isOn: $store.showHidden)
                Toggle("파일 유형별 색상", isOn: $store.colorByType)
            } label: { Image(systemName: "slider.horizontal.3") }.menuStyle(.borderlessButton).frame(width: 22).help("표시 설정")
            Button { store.listMode.toggle() } label: { Image(systemName: store.listMode ? "square.grid.2x2" : "list.bullet") }.buttonStyle(.plain).help("트리맵 / 목록 전환")
        }.padding(.horizontal, 13).frame(height: 38).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 20).padding(.bottom, 10)
    }
    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(store.visibleChildren, id: \.self) { id in
                    if let node = store.node(id) {
                        HStack(spacing: 10) {
                            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill").foregroundStyle(FileCategory.of(node).color).frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.name).font(.system(size: 12)).lineLimit(1)
                                Text(node.modified.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.effectiveTag(id) > 0 { Circle().fill(Color(nsColor: tagColors[store.effectiveTag(id)])).frame(width: 7, height: 7) }
                            Text(formattedBytes(store.weights[id])).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            Button { store.open(id) } label: { Image(systemName: node.isDirectory ? "chevron.right" : "arrow.up.right") }.buttonStyle(.plain).disabled(store.offline && !node.isDirectory)
                        }.padding(12).background(store.selected == id ? accent.opacity(0.10) : .white.opacity(0.02), in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle()).onTapGesture { store.selected = id }
                            .contextMenu { contextActions(id) }
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 4)
        }.frame(maxHeight: .infinity)
    }
    private var inspector: some View {
        let node = store.selectedNode ?? store.focusedNode
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.selectedNode == nil ? "현재 위치" : "선택한 항목").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 25)
                if let node {
                    Image(systemName: node.isDirectory ? "folder.fill" : node.isSymbolicLink ? "link" : "doc.fill")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(FileCategory.of(node).color).padding(.bottom, 15)
                    Text(node.name).font(.system(size: 17, weight: .medium)).textSelection(.enabled).padding(.bottom, 8)
                    Text(node.path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled).lineSpacing(3).padding(.bottom, 23)
                    infoRow("디스크 사용량", formattedBytes(node.allocatedBytes))
                    infoRow("파일 크기", formattedBytes(node.logicalBytes))
                    infoRow("유형", node.isSymbolicLink ? "심볼릭 링크" : FileCategory.of(node).title)
                    if node.isDirectory { infoRow("직접 하위 항목", "\(node.children.count.formatted())개") }
                    infoRow("수정일", node.modified.formatted(date: .numeric, time: .shortened))
                    if let issue = node.issue { Text(issue).font(.caption).foregroundStyle(.orange).padding(.top, 10) }
                    Divider().padding(.vertical, 20)
                    Text("색상 태그").font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 12)
                    HStack(spacing: 13) {
                        ForEach(1...4, id: \.self) { color in
                            Button { store.tag(node.id, color: color) } label: {
                                Circle().fill(Color(nsColor: tagColors[color])).frame(width: 14, height: 14)
                                    .overlay { if store.effectiveTag(node.id) == color { Circle().stroke(.white, lineWidth: 1.5).padding(-3) } }
                            }.buttonStyle(.plain).help(["", "빨강", "노랑", "초록", "파랑"][color] + " 태그")
                        }
                        Button { store.tag(node.id, color: 0) } label: { Image(systemName: "xmark.circle").font(.system(size: 14)).foregroundStyle(.secondary) }.buttonStyle(.plain).help("직접 지정한 태그 해제")
                    }
                    Divider().padding(.vertical, 20)
                    Button { store.reveal(node.id) } label: { Label("Finder에서 보기", systemImage: "arrow.up.forward.square").frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(.plain).font(.system(size: 11)).disabled(store.offline).padding(.bottom, 14)
                    Button { store.copyPath(node.id) } label: { Label("경로 복사", systemImage: "doc.on.doc").frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(.plain).font(.system(size: 11)).padding(.bottom, 14)
                    if node.id != 0 {
                        Button { store.trash(node.id) } label: { Label("휴지통으로 이동…", systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8)).disabled(store.offline || store.isScanning)
                    }
                }
                if let snapshot = store.snapshot, snapshot.volumeTotal > 0 {
                    Divider().padding(.vertical, 24)
                    Text("볼륨 전체").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.bottom, 12)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(accent.opacity(0.7)).frame(width: geometry.size.width * min(1, max(0, Double(snapshot.volumeTotal - snapshot.volumeFree) / Double(snapshot.volumeTotal))))
                        }
                    }.frame(height: 5).padding(.bottom, 12)
                    infoRow("전체", formattedBytes(snapshot.volumeTotal)); infoRow("여유 공간", formattedBytes(snapshot.volumeFree))
                    infoRow("시스템 사용량", formattedBytes(max(0, snapshot.volumeTotal - snapshot.volumeFree)))
                    Text("APFS 공유·압축·스냅샷과 접근 권한 때문에 스캔 합계와 볼륨 사용량은 다를 수 있습니다.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(4).padding(.top, 10)
                }
            }.padding(22)
        }.background(panel.opacity(0.5))
    }
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) { Text(title).foregroundStyle(.secondary); Spacer(minLength: 0); Text(value).multilineTextAlignment(.trailing) }.font(.system(size: 10)).padding(.vertical, 6)
    }
    @ViewBuilder private func contextActions(_ id: Int) -> some View {
        Button("열기") { store.open(id) }.disabled(store.offline && store.node(id)?.isDirectory != true)
        Button("Finder에서 보기") { store.reveal(id) }.disabled(store.offline)
        Button("경로 복사") { store.copyPath(id) }
        Divider()
        ForEach(1...4, id: \.self) { color in Button(["", "🔴 빨강", "🟡 노랑", "🟢 초록", "🔵 파랑"][color]) { store.tag(id, color: color) } }
        Button("태그 해제") { store.tag(id, color: 0) }
        Divider()
        Button("휴지통으로 이동…", role: .destructive) { store.trash(id) }.disabled(store.offline || store.isScanning || id == 0)
    }
    private func tool(_ icon: String, _ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 11, weight: .medium)).frame(width: 25, height: 25).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(disabled).foregroundStyle(disabled ? .white.opacity(0.15) : .white.opacity(0.65)).help(title).accessibilityLabel(title)
    }
    private func inlineMessage(_ text: String, color: Color) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(color).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.05)) }
    private var statusbar: some View {
        HStack(spacing: 8) {
            Circle().fill(store.isScanning ? .orange : accent).frame(width: 5, height: 5)
            Text(store.isScanning ? "스캔 중 · 일부 결과" : store.snapshot == nil ? "준비됨" : store.offline ? "저장된 결과" : store.snapshot?.cancelled == true ? "중지됨 · 일부 결과" : (store.snapshot?.issueCount ?? 0) > 0 ? "검사 종료 · 접근 오류 있음" : "스캔 완료").font(.system(size: 10))
            if let snapshot = store.snapshot {
                Text("·").foregroundStyle(.tertiary)
                let progress = store.isScanning && store.scanProgress?.rootPath == snapshot.rootPath ? store.scanProgress : nil
                Text("파일 \((progress?.fileCount ?? snapshot.fileCount).formatted()) · 폴더 \((progress?.folderCount ?? snapshot.folderCount).formatted())").font(.system(size: 10)).foregroundStyle(.secondary)
                if snapshot.issueCount > 0 { Button("접근 오류 \(snapshot.issueCount)개") { store.showIssues = true }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.orange) }
                if let finished = snapshot.finished {
                    Text(String(format: "· %.1f초", finished.timeIntervalSince(snapshot.started))).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if !store.offline, let coverage = store.snapshot?.volumeCoverage {
                Text(coverage.traversal == .allVolumes ? "다른 볼륨 포함" : "선택 볼륨만")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                if coverage.excludedCount > 0 {
                    Text("볼륨·중복 경계 \(coverage.excludedCount)곳 제외")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .help(coverage.exclusions.map { $0.path }.joined(separator: "\n"))
                }
            }
            if store.watchActive && !store.offline && store.snapshot != nil { Label("변경 시 자동 재스캔", systemImage: "waveform.path").font(.system(size: 9)).foregroundStyle(.secondary) }
            Text("로컬 분석").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 18).frame(height: 31).background(panel)
    }
    private var issuesSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("스캔 중 읽지 못한 경로").font(.title2)
            Text("시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에서 앱을 허용한 뒤 다시 스캔할 수 있습니다. 오류 기록은 최대 500개까지 표시합니다.").font(.callout).foregroundStyle(.secondary)
            ScrollView { Text(store.snapshot?.issues.joined(separator: "\n\n") ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Spacer(); Button("닫기") { store.showIssues = false }.keyboardShortcut(.defaultAction) }
        }.padding(25).frame(width: 720, height: 480).preferredColorScheme(.dark)
    }
}
