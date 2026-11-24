use crate::layout::Tile;
use crate::{
    backend::{Event, ScanSession},
    model::{Progress, Snapshot},
    platform,
    projection::{Projection, SizeMode},
    watch::ChangeMonitor,
};
use gpui_kit::base::input::{InputEvent, InputState};
use gpui_kit::*;
use std::{
    cell::RefCell,
    path::PathBuf,
    rc::Rc,
    sync::{Arc, mpsc},
    time::{Duration, Instant},
};
#[derive(Clone, Debug)]
pub enum Command {
    Browse,
    NewWindow,
    Quit,
    CloseWindow,
    Minimize,
    HideWindow,
    ChooseDocument(Option<usize>),
    Scan,
    Cancel,
    Rescan,
    RescanFocus,
    Up,
    Back,
    Forward,
    List,
    Settings,
    More,
    Help,
    SetDepth(usize),
    Color,
    Root,
    Logical,
    Hidden,
    Watch,
    MountedVolumes,
    Filter,
    Save,
    Load,
    Export,
    ConfiguredExport,
    Issues,
    DismissError,
    Navigate(usize),
    NavigatePath(PathBuf),
    Select(usize),
    Tag(u8),
    CopyPath,
    Reveal,
    Open,
    Preview,
    ZoomSelected,
    ClearTags,
    ClearFilter,
    Trash,
}
pub struct Explorer {
    pub focus_handle: FocusHandle,
    pub(super) control_window_id: String,
    pub(super) view_revision: u64,
    pub(super) document_open_id: u64,
    pub(super) pending_import: Option<Arc<crate::document::NativeProcess>>,
    pub(super) document_choice: Option<super::document_choices::DocumentChoice>,
    pub path_input: Entity<InputState>,
    pub filter_input: Entity<InputState>,
    pub snapshot: Option<Arc<Snapshot>>,
    pub projection: Option<Projection>,
    pub progress: Option<Progress>,
    pub root: PathBuf,
    pub workspace: super::navigation::ScanWorkspace,
    pub volumes: Vec<PathBuf>,
    pub focus: usize,
    pub selected: Option<usize>,
    pub hovered: Option<usize>,
    pub(super) projection_work: crate::latest_work::LatestWork,
    pub tags: std::collections::HashMap<String, u8>,
    pub context_menu: Option<Point<Pixels>>,
    pub click_anchor: Option<(usize, String)>,
    pub history: Vec<crate::navigation::Location>,
    pub future: Vec<crate::navigation::Location>,
    pub depth: usize,
    pub list_mode: bool,
    pub settings: bool,
    pub more_menu: bool,
    pub filter_help: bool,
    pub color_by_type: bool,
    pub presentation: Rc<RefCell<crate::motion::Presentation>>,
    pub geometry: Rc<RefCell<crate::layout::GeometryCache>>,
    pub mode: SizeMode,
    pub hidden: bool,
    pub watching: bool,
    pub(super) native_watch_active: bool,
    pub include_mounted: bool,
    pub offline: bool,
    pub scanning: bool,
    pub status: String,
    pub filter_error: String,
    pub error_dialog: Option<String>,
    pub show_issues: bool,
    pub tiles: Rc<RefCell<Vec<Tile>>>,
    pub(super) session: Option<ScanSession>,
    pub(super) monitor: Option<ChangeMonitor>,
    pub(super) changed: Option<Instant>,
    pub(super) projection_rx: Option<mpsc::Receiver<anyhow::Result<Projection>>>,
    _subscriptions: Vec<Subscription>,
}
impl Explorer {
    pub fn new(
        initial: Option<PathBuf>,
        qa_output: Option<PathBuf>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let root = initial
            .clone()
            .or_else(std::env::home_dir)
            .unwrap_or_default();
        let root = platform::scan_path(&root);
        let path_input = cx.new(|cx| InputState::new(window, cx).placeholder("분석할 폴더 경로"));
        path_input.update(cx, |input, cx| {
            input.set_value(root.to_string_lossy().to_string(), window, cx)
        });
        let filter_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("필터: *.zip;>100MB 또는 |*.tmp"));
        let subscriptions = vec![
            cx.subscribe_in(&path_input, window, |this, _, event, window, cx| {
                if matches!(event, InputEvent::PressEnter { .. }) {
                    this.command(Command::Scan, window, cx)
                }
            }),
            cx.subscribe_in(&filter_input, window, |this, _, event, window, cx| {
                if matches!(event, InputEvent::PressEnter { .. }) {
                    this.command(Command::Filter, window, cx)
                }
            }),
        ];
        cx.spawn(async move |this, cx| {
            loop {
                cx.background_executor()
                    .timer(Duration::from_millis(50))
                    .await;
                if this.update(cx, |this, cx| this.poll(cx)).is_err() {
                    break;
                }
            }
        })
        .detach();
        cx.spawn(async move |this, cx| {
            loop {
                let volumes = cx
                    .background_executor()
                    .spawn(async { platform::volumes() })
                    .await;
                if this
                    .update(cx, |this, cx| {
                        if this.volumes != volumes {
                            this.volumes = volumes;
                            cx.notify();
                        }
                    })
                    .is_err()
                {
                    break;
                }
                cx.background_executor().timer(Duration::from_secs(3)).await;
            }
        })
        .detach();
        let focus_handle = cx.focus_handle();
        window.focus(&focus_handle, cx);
        let mut app = Self {
            focus_handle,
            control_window_id: format!("{:?}", window.window_handle().window_id()),
            view_revision: 0,
            document_open_id: 0,
            pending_import: None,
            document_choice: None,
            path_input,
            filter_input,
            snapshot: None,
            projection: None,
            progress: None,
            workspace: super::navigation::ScanWorkspace {
                scope: root.clone(),
                ..Default::default()
            },
            root,
            volumes: vec![],
            focus: 0,
            selected: None,
            hovered: None,
            projection_work: crate::latest_work::LatestWork::new(),
            tags: Default::default(),
            context_menu: None,
            click_anchor: None,
            history: vec![],
            future: vec![],
            depth: 3,
            list_mode: false,
            settings: false,
            more_menu: false,
            filter_help: false,
            color_by_type: true,
            presentation: Rc::new(RefCell::new(Default::default())),
            geometry: Rc::new(RefCell::new(Default::default())),
            mode: SizeMode::Allocated,
            hidden: true,
            watching: true,
            native_watch_active: false,
            include_mounted: false,
            offline: false,
            scanning: false,
            status: "폴더를 선택하고 분석을 시작하세요.".into(),
            filter_error: String::new(),
            error_dialog: None,
            show_issues: false,
            tiles: Rc::new(RefCell::new(vec![])),
            session: None,
            monitor: None,
            changed: None,
            projection_rx: None,
            _subscriptions: subscriptions,
        };
        if initial.is_some() {
            if app.root.is_file() {
                app.open_snapshot_file(app.root.clone(), window, cx)
            } else {
                app.start(cx)
            }
        }
        #[cfg(feature = "qa")]
        if let Some(output) = qa_output {
            super::qa::install(&mut app, output, window, cx);
        }
        #[cfg(not(feature = "qa"))]
        let _ = qa_output;
        app
    }
    pub fn uses_progress_map(&self) -> bool {
        self.progress.is_some() && self.focus == 0 && (self.projection.is_none() || self.scanning)
    }
    pub fn command(&mut self, command: Command, window: &mut Window, cx: &mut Context<Self>) {
        self.context_menu = None;
        match command {
            Command::Quit => cx.quit(),
            Command::CloseWindow => window.remove_window(),
            Command::Minimize => {
                let _ = crate::platform::window_state(window, "minimized");
            }
            Command::HideWindow => {
                let _ = crate::platform::window_state(window, "hidden");
            }
            Command::NewWindow => {
                if let Err(error) = super::windows::open(None, cx) {
                    self.error_dialog = Some(error.to_string());
                }
            }
            Command::ChooseDocument(None) => self.cancel_import(),
            Command::ChooseDocument(choice) => self.finish_document_choice(choice),
            Command::Tag(color) => self.tag_node(self.selected.unwrap_or(self.focus), color, cx),
            Command::CopyPath => {
                if let Some(node) = self
                    .snapshot
                    .as_ref()
                    .and_then(|s| s.nodes.get(self.selected.unwrap_or(self.focus)))
                {
                    cx.write_to_clipboard(ClipboardItem::new_string(node.path.clone()));
                }
            }
            Command::Reveal => {
                if !self.offline
                    && let Some(node) = self
                        .snapshot
                        .as_ref()
                        .and_then(|s| s.nodes.get(self.selected.unwrap_or(self.focus)))
                {
                    cx.reveal_path(std::path::Path::new(&node.path));
                }
            }
            Command::ClearFilter => {
                self.filter_input
                    .update(cx, |input, cx| input.set_value("", window, cx));
                self.refresh(cx);
            }
            Command::ClearTags => {
                let scope = self.focus_path();
                self.tags.retain(|path, _| {
                    !crate::navigation::contains(&scope, std::path::Path::new(path))
                });
                self.projection = None;
                self.refresh(cx);
            }
            Command::ZoomSelected => {
                if let Some(id) = self.selected
                    && let Some(node) = self.snapshot.as_ref().and_then(|s| s.nodes.get(id))
                {
                    let target = if node.directory {
                        Some(id)
                    } else {
                        node.parent
                    };
                    if let Some(target) = target {
                        self.command(Command::Navigate(target), window, cx)
                    }
                }
            }
            Command::Preview => self.preview_selected(cx),
            Command::Open => {
                let id = self.selected.unwrap_or(self.focus);
                if let Some(node) = self.snapshot.as_ref().and_then(|s| s.nodes.get(id)) {
                    if node.directory {
                        self.command(Command::Navigate(id), window, cx);
                    } else if !self.offline {
                        cx.open_with_system(std::path::Path::new(&node.path));
                    }
                }
            }
            Command::Trash => self.trash(window, cx),

            Command::Scan => {
                let path = PathBuf::from(self.path_input.read(cx).value().to_string());
                self.choose(path, window, cx)
            }
            Command::Cancel => {
                self.cancel_import();
                for doc in self.workspace.parked.values() {
                    if let Some(s) = &doc.session {
                        s.cancel();
                    }
                }
                if let Some(s) = &self.session {
                    s.cancel();
                    self.status = "중지 요청 · 진행 중 파일 작업을 정리하는 중".into()
                }
            }
            Command::Rescan => self.request_rescan(false, cx),
            Command::RescanFocus => self.request_rescan(true, cx),
            Command::Browse => {
                let paths = cx.prompt_for_paths(PathPromptOptions {
                    files: false,
                    directories: true,
                    multiple: false,
                    prompt: Some("분석할 폴더 선택".into()),
                });
                cx.spawn_in(window, async move |this, cx| {
                    if let Ok(Ok(Some(paths))) = paths.await
                        && let Some(path) = paths.into_iter().next()
                    {
                        let _ =
                            this.update_in(cx, |this, window, cx| this.choose(path, window, cx));
                    }
                })
                .detach();
            }
            Command::NavigatePath(path) => self.navigate_path(path, window, cx),
            Command::Navigate(id) => {
                if let Some(n) = self.snapshot.as_ref().and_then(|s| s.nodes.get(id)) {
                    if n.directory {
                        self.navigate_path(PathBuf::from(&n.path), window, cx)
                    } else {
                        self.selected = Some(id)
                    }
                }
            }
            Command::Select(id) => self.selected = Some(id),
            Command::Root => self.navigate_path(self.workspace.scope.clone(), window, cx),
            Command::Up => {
                if self.can_up()
                    && let Some(parent) = crate::navigation::parent(&self.focus_path())
                {
                    self.navigate_path(parent.to_path_buf(), window, cx)
                }
            }
            Command::Back => self.move_history(false, window, cx),
            Command::Forward => self.move_history(true, window, cx),
            Command::List => self.list_mode = !self.list_mode,
            Command::Settings => self.settings = !self.settings,
            Command::More => self.more_menu = !self.more_menu,
            Command::Help => self.filter_help = !self.filter_help,
            Command::SetDepth(depth) => {
                self.depth = depth;
                self.settings = false;
            }
            Command::Color => self.color_by_type = !self.color_by_type,
            Command::Logical => {
                self.mode = if self.mode == SizeMode::Allocated {
                    SizeMode::Logical
                } else {
                    SizeMode::Allocated
                };
                self.refresh(cx)
            }
            Command::Hidden => {
                self.hidden = !self.hidden;
                self.refresh(cx)
            }
            Command::Filter => self.refresh(cx),
            Command::MountedVolumes => {
                if platform::mounted_volumes_supported() && !self.offline {
                    self.include_mounted = !self.include_mounted;
                    self.choose(self.workspace.scope.clone(), window, cx);
                }
            }
            Command::Watch => {
                self.watching = !self.watching;
                let command = if self.watching {
                    "watch true"
                } else {
                    "watch false"
                };
                if self.root == self.workspace.scope {
                    self.configure_monitor();
                    if let Some(s) = &self.session {
                        s.send(command)
                    }
                } else if let Some(root) = self.workspace.parked.get_mut(&self.workspace.scope) {
                    if let Some(s) = &root.session {
                        s.send(command)
                    }
                    if !platform::engine_watches() {
                        root.monitor = if self.watching {
                            ChangeMonitor::start(&root.root).ok()
                        } else {
                            None
                        };
                        root.changed = None;
                    }
                }
            }
            Command::Save => self.save(false, window, cx),
            Command::Export => self.save(true, window, cx),
            Command::ConfiguredExport => self.configured_export(window, cx),
            Command::Load => self.load(window, cx),
            Command::Issues => self.show_issues = !self.show_issues,
            Command::DismissError => self.error_dialog = None,
        }
        cx.notify();
    }
    pub fn open_location(&mut self, path: PathBuf, window: &mut Window, cx: &mut Context<Self>) {
        if path.is_file() {
            self.open_snapshot_file(path, window, cx)
        } else {
            self.choose(path, window, cx)
        }
    }
    pub(super) fn choose(&mut self, path: PathBuf, window: &mut Window, cx: &mut Context<Self>) {
        let path = platform::scan_path(&path);
        self.cancel_import();
        self.session = None;
        self.monitor = None;
        self.scanning = false;
        self.reset_workspace(path.clone());
        self.tags.clear();
        self.root = path;
        self.path_input.update(cx, |state, cx| {
            state.set_value(self.root.to_string_lossy().to_string(), window, cx)
        });
        self.start(cx)
    }
    pub(super) fn start(&mut self, cx: &mut Context<Self>) {
        if self.scanning {
            return;
        }
        self.monitor = None;
        self.changed = None;
        self.session = None;
        if self.snapshot.as_ref().is_none_or(|s| s.root != self.root) {
            self.snapshot = None;
            self.projection = None;
            self.focus = 0;
            self.selected = None;
            self.tiles.borrow_mut().clear();
            self.hovered = None;
        }
        self.progress = None;
        self.native_watch_active = false;
        self.offline = false;
        self.status = "분석 시작".into();
        match ScanSession::start_scoped(
            &platform::backend(),
            &self.root,
            self.watching && self.root == self.workspace.scope,
            self.include_mounted,
        ) {
            Ok(session) => {
                self.scanning = true;
                self.session = Some(session);
                self.configure_monitor();
            }
            Err(e) => {
                self.status = e.to_string();
                self.scanning = false;
            }
        }
        cx.notify();
    }
    fn configure_monitor(&mut self) {
        self.monitor = None;
        if self.watching
            && self.root == self.workspace.scope
            && !self.offline
            && !platform::engine_watches()
        {
            match ChangeMonitor::start(&self.root) {
                Ok(w) => self.monitor = Some(w),
                Err(e) => self.status = format!("변경 감시 오류: {e}"),
            }
        }
    }
    pub(super) fn refresh(&mut self, cx: &mut Context<Self>) {
        let Some(source) = self.snapshot.clone() else {
            return;
        };
        let focus = self.focus;
        let text = self.filter_input.read(cx).value().to_string();
        let mode = self.mode;
        let hidden = self.hidden;
        self.view_revision = self.view_revision.wrapping_add(1);
        self.filter_error.clear();
        let previous = self.projection.clone();
        let tags = self.tags.clone();
        self.projection_rx = Some(self.projection_work.submit(move || {
            previous
                .and_then(|p| p.refocus(&source, focus, &text, mode, hidden))
                .map(Ok)
                .unwrap_or_else(|| {
                    Projection::build_with_tags(source, focus, &text, mode, hidden, &tags)
                })
        }));
        cx.notify();
    }
    fn poll(&mut self, cx: &mut Context<Self>) {
        if let Some(message) = platform::preview_message() {
            self.status = format!("미리보기 오류: {message}");
            cx.notify();
        }
        for doc in self.workspace.parked.values_mut() {
            doc.poll(self.include_mounted);
        }
        let events: Vec<_> = self
            .session
            .as_ref()
            .map(|s| s.events.try_iter().collect())
            .unwrap_or_default();
        let mut dirty = false;
        for event in events {
            dirty = true;
            match event {
                Event::WatchActive(active) => {
                    self.native_watch_active = active;
                }
                Event::Progress(p) => {
                    self.scanning = true;
                    self.status = format!(
                        "분석 중 · 파일 {} · 폴더 {} · 대기 {} · 오류 {}",
                        p.files, p.folders, p.pending, p.errors
                    );
                    self.progress = Some(p);
                }
                Event::Complete(source) => {
                    self.scanning = false;
                    self.status = format!(
                        "{} · 파일 {} · 폴더 {} · {:.2}초 · 오류 {} · 경계 제외 {}",
                        if source.cancelled {
                            "중지됨"
                        } else {
                            "분석 완료"
                        },
                        source.files,
                        source.folders,
                        source.elapsed,
                        source.errors,
                        source.excluded
                    );
                    if !source.cancelled || self.snapshot.is_none() {
                        let focus_path = self
                            .snapshot
                            .as_ref()
                            .and_then(|s| s.nodes.get(self.focus))
                            .map(|n| n.path.clone());
                        let selected_path = self
                            .snapshot
                            .as_ref()
                            .and_then(|s| self.selected.and_then(|id| s.nodes.get(id)))
                            .map(|n| n.path.clone());
                        self.focus = focus_path
                            .as_deref()
                            .and_then(|path| source.node_at_path(path))
                            .unwrap_or(0);
                        self.selected = selected_path
                            .as_deref()
                            .and_then(|path| source.node_at_path(path));
                        self.projection = None;
                        self.tiles.borrow_mut().clear();
                        self.hovered = None;
                        self.snapshot = Some(source);
                        self.refresh(cx);
                    }
                }
                Event::ImportRoots(_) | Event::ImportCodePage | Event::ImportInspection(_) => {}
                Event::Failure(e) => {
                    self.scanning = false;
                    self.error_dialog = Some(e.clone());
                    self.status = e;
                    self.progress = None;
                }
            }
        }
        if let Some(m) = &self.monitor {
            for time in m.events.try_iter() {
                self.changed = Some(time)
            }
        }
        if !self.scanning
            && self
                .changed
                .is_some_and(|t| t.elapsed() > Duration::from_millis(750))
        {
            self.changed = None;
            self.request_rescan(false, cx);
            dirty = true;
        }
        if let Some(rx) = &self.projection_rx
            && let Ok(result) = rx.try_recv()
        {
            match result {
                Ok(p) => {
                    self.projection = Some(p);
                    if !self.scanning {
                        self.progress = None;
                    }
                }
                Err(e) => self.filter_error = e.to_string(),
            }
            self.projection_rx = None;
            dirty = true;
        }
        if dirty {
            cx.notify();
        }
    }
}
