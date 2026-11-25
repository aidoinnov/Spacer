use super::{app::Explorer, scan_document::ScanDocument};
use crate::navigation::{Location, breadcrumbs};
use gpui_kit::*;
use std::{collections::HashMap, mem, path::PathBuf};
#[derive(Default)]
pub struct ScanWorkspace {
    pub scope: PathBuf,
    pub parked: HashMap<PathBuf, ScanDocument>,
}
impl Explorer {
    pub fn focus_node_is_directory(&self) -> bool {
        self.snapshot
            .as_ref()
            .and_then(|s| s.nodes.get(self.focus))
            .is_some_and(|n| n.directory)
    }
    pub fn focus_path(&self) -> PathBuf {
        self.snapshot
            .as_ref()
            .and_then(|s| s.nodes.get(self.focus))
            .map(|n| PathBuf::from(&n.path))
            .unwrap_or_else(|| self.root.clone())
    }
    pub fn current_location(&self) -> Location {
        Location {
            document: self.root.clone(),
            focus: self.focus_path(),
        }
    }
    pub fn breadcrumb_paths(&self) -> Vec<PathBuf> {
        breadcrumbs(&self.workspace.scope, &self.focus_path())
    }
    pub fn can_up(&self) -> bool {
        self.focus_path() != self.workspace.scope
    }
    fn resolve_location(&self, path: PathBuf) -> Location {
        if self
            .snapshot
            .as_ref()
            .is_some_and(|s| s.node_at_path(&path.to_string_lossy()).is_some())
        {
            return Location {
                document: self.root.clone(),
                focus: path,
            };
        }
        if let Some(root) = self.workspace.parked.get(&self.workspace.scope)
            && root
                .snapshot
                .as_ref()
                .is_some_and(|s| s.node_at_path(&path.to_string_lossy()).is_some())
        {
            return Location {
                document: self.workspace.scope.clone(),
                focus: path,
            };
        }
        Location::root(path)
    }
    pub fn navigate_path(&mut self, path: PathBuf, window: &mut Window, cx: &mut Context<Self>) {
        let Some(path) = crate::navigation::resolve_contained_path(
            &self.workspace.scope,
            path,
            crate::platform::scan_path,
        ) else {
            return;
        };
        if path == self.focus_path() {
            return;
        }
        let target = self.resolve_location(path);
        self.history.push(self.current_location());
        self.future.clear();
        self.activate_location(target, window, cx);
    }
    pub fn move_history(&mut self, forward: bool, window: &mut Window, cx: &mut Context<Self>) {
        let target = if forward {
            self.future.pop()
        } else {
            self.history.pop()
        };
        if let Some(target) = target {
            let current = self.current_location();
            if forward {
                self.history.push(current)
            } else {
                self.future.push(current)
            }
            self.activate_location(target, window, cx);
        }
    }
    fn take_document(&mut self) -> ScanDocument {
        ScanDocument {
            root: self.root.clone(),
            snapshot: self.snapshot.take(),
            projection: self.projection.take(),
            progress: self.progress.take(),
            focus: self.focus,
            selected: self.selected.take(),
            scanning: self.scanning,
            native_watch_active: self.native_watch_active,
            offline: self.offline,
            status: mem::take(&mut self.status),
            session: self.session.take(),
            monitor: self.monitor.take(),
            changed: self.changed.take(),
            projection_rx: self.projection_rx.take(),
        }
    }
    fn restore_document(&mut self, d: ScanDocument) {
        self.root = d.root;
        self.snapshot = d.snapshot;
        self.projection = d.projection;
        self.progress = d.progress;
        self.focus = d.focus;
        self.selected = d.selected;
        self.scanning = d.scanning;
        self.native_watch_active = d.native_watch_active;
        self.offline = d.offline;
        self.status = d.status;
        self.session = d.session;
        self.monitor = d.monitor;
        self.changed = d.changed;
        self.projection_rx = d.projection_rx;
        self.tiles.borrow_mut().clear();
        self.hovered = None;
        self.click_anchor = None;
    }
    fn activate_location(&mut self, target: Location, window: &mut Window, cx: &mut Context<Self>) {
        if target.document != self.root {
            let mut current = self.take_document();
            if current.root != self.workspace.scope {
                current.session = None;
                current.monitor = None;
                current.scanning = false;
            }
            let old_root = current.root.clone();
            self.workspace.parked.insert(old_root, current);
            let next = self
                .workspace
                .parked
                .remove(&target.document)
                .unwrap_or_else(|| ScanDocument::empty(target.document.clone()));
            self.restore_document(next);
            // Only the original scan and the visible branch run. Keep a small result cache.
            while self.workspace.parked.len() > 3 {
                let evict = self
                    .workspace
                    .parked
                    .keys()
                    .find(|p| **p != self.workspace.scope)
                    .cloned();
                if let Some(key) = evict {
                    if let Some(doc) = self.workspace.parked.remove(&key) {
                        std::thread::spawn(move || drop(doc));
                    }
                } else {
                    break;
                }
            }
        }
        self.path_input.update(cx, |input, cx| {
            input.set_value(self.root.display().to_string(), window, cx)
        });
        if let Some(source) = &self.snapshot {
            self.focus = source
                .node_at_path(&target.focus.to_string_lossy())
                .unwrap_or(0);
            self.selected = None;
            self.refresh(cx)
        } else if !self.scanning {
            self.start(cx)
        }
        cx.notify();
    }
    pub fn reset_workspace(&mut self, path: PathBuf) {
        let parked = mem::take(&mut self.workspace.parked);
        let snapshot = self.snapshot.take();
        let projection = self.projection.take();
        let pending = self.projection_rx.take();
        let geometry = mem::take(&mut *self.geometry.borrow_mut());
        // Large graphs and their native document owners are released off the UI lane.
        std::thread::spawn(move || drop((parked, snapshot, projection, pending, geometry)));
        self.workspace.scope = path;
        self.history.clear();
        self.future.clear();
    }
}
