//! A parked scan retains its engine and current result while the user visits a branch.
use crate::{
    backend::{Event, ScanSession},
    model::{Progress, Snapshot},
    projection::Projection,
    watch::ChangeMonitor,
};
use std::{
    path::PathBuf,
    sync::{Arc, mpsc},
    time::Instant,
};
pub struct ScanDocument {
    pub root: PathBuf,
    pub snapshot: Option<Arc<Snapshot>>,
    pub projection: Option<Projection>,
    pub progress: Option<Progress>,
    pub focus: usize,
    pub selected: Option<usize>,
    pub scanning: bool,
    pub native_watch_active: bool,
    pub offline: bool,
    pub status: String,
    pub session: Option<ScanSession>,
    pub monitor: Option<ChangeMonitor>,
    pub changed: Option<Instant>,
    pub projection_rx: Option<mpsc::Receiver<anyhow::Result<Projection>>>,
}
impl ScanDocument {
    pub fn empty(root: PathBuf) -> Self {
        Self {
            root,
            snapshot: None,
            projection: None,
            progress: None,
            focus: 0,
            selected: None,
            scanning: false,
            native_watch_active: false,
            offline: false,
            status: "분석 시작".into(),
            session: None,
            monitor: None,
            changed: None,
            projection_rx: None,
        }
    }
    pub fn poll(&mut self, include_mounted: bool) {
        let events: Vec<_> = self
            .session
            .as_ref()
            .map(|s| s.events.try_iter().collect())
            .unwrap_or_default();
        for event in events {
            match event {
                Event::WatchActive(active) => {
                    self.native_watch_active = active;
                }
                Event::Progress(p) => {
                    self.scanning = true;
                    self.progress = Some(p)
                }
                Event::Complete(s) => {
                    self.scanning = false;
                    if !s.cancelled || self.snapshot.is_none() {
                        let path = self
                            .snapshot
                            .as_ref()
                            .and_then(|s| s.nodes.get(self.focus))
                            .map(|n| n.path.clone());
                        self.focus = path.and_then(|p| s.node_at_path(&p)).unwrap_or(0);
                        self.snapshot = Some(s);
                        self.projection = None;
                        self.projection_rx = None;
                        self.selected = None;
                    }
                    self.status = if self.snapshot.as_ref().is_some_and(|s| s.cancelled) {
                        "중지됨"
                    } else {
                        "분석 완료"
                    }
                    .into();
                }
                Event::ImportRoots(_) | Event::ImportCodePage | Event::ImportInspection(_) => {}
                Event::Failure(e) => {
                    self.scanning = false;
                    self.status = e;
                }
            }
        }
        if let Some(monitor) = &self.monitor {
            for at in monitor.events.try_iter() {
                self.changed = Some(at)
            }
        }
        if !self.scanning
            && self
                .changed
                .is_some_and(|at| at.elapsed() > std::time::Duration::from_millis(750))
        {
            self.changed = None;
            if let Some(session) = &self.session
                && session.is_alive()
            {
                session.send("rescan");
                self.scanning = true;
                self.progress = None;
                return;
            }
            match ScanSession::start_scoped(
                &crate::platform::backend(),
                &self.root,
                true,
                include_mounted,
            ) {
                Ok(session) => {
                    self.session = Some(session);
                    self.scanning = true;
                    self.progress = None;
                }
                Err(error) => self.status = error.to_string(),
            }
        }
    }
}
