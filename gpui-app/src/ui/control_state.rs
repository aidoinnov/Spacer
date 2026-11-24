//! Immutable controller payloads and document revision identity.
use super::app::Explorer;
use gpui_kit::*;
use serde_json::{Value, json};
fn scan_document(
    root: &std::path::Path,
    source: Option<&crate::model::Snapshot>,
    scanning: bool,
    offline: bool,
    status: &str,
) -> Value {
    json!({"document_root":root,"scanning":scanning,"offline":offline,"status":status,
        "version":source.and_then(|s|s.document.as_ref().map(|d|d.version.clone()).or_else(||s.wire_version.clone())),
        "files":source.map(|s|s.files),"folders":source.map(|s|s.folders),"issues":source.map(|s|s.errors),"cancelled":source.map(|s|s.cancelled)})
}
pub(super) fn window_id(handle: WindowHandle<Explorer>) -> String {
    format!("{:?}", handle.window_id())
}
pub(super) fn state_with_window(app: &Explorer, window: &Window, cx: &App) -> Value {
    let mut state = app.control_state(cx);
    if let Some(observation) = crate::platform::window_observation(window).as_object() {
        for (key, value) in observation {
            state[key] = value.clone();
        }
    }
    state
}
impl Explorer {
    pub(super) fn document_command(&self, cx: &App) -> Value {
        json!({"filter":self.filter_input.read(cx).value().to_string(),"logical":self.mode==crate::projection::SizeMode::Logical,"hidden":self.hidden,"root":self.focus,"tags":self.tags,"queryRevision":self.control_revision()})
    }
    fn control_revision(&self) -> String {
        format!(
            "{}:{}",
            self.snapshot
                .as_ref()
                .and_then(|s| s.document.as_ref())
                .map(|d| d.version.as_str())
                .unwrap_or("none"),
            self.view_revision
        )
    }
    pub(super) fn control_state(&self, cx: &App) -> Value {
        let source = self.snapshot.as_ref();
        let mut documents = vec![scan_document(
            &self.root,
            source.map(|s| s.as_ref()),
            self.scanning,
            self.offline,
            &self.status,
        )];
        documents.extend(self.workspace.parked.values().map(|d| {
            scan_document(
                &d.root,
                d.snapshot.as_deref(),
                d.scanning,
                d.offline,
                &d.status,
            )
        }));
        documents.sort_by(|a, b| {
            a["document_root"]
                .as_str()
                .cmp(&b["document_root"].as_str())
        });
        let selected = self
            .selected
            .and_then(|id| source.and_then(|s| s.nodes.get(id)))
            .map(|n| &n.path);
        let phase = if self.scanning {
            "scanning"
        } else if self.offline {
            "offline"
        } else if self.error_dialog.is_some() {
            "failed"
        } else if source.is_some_and(|s| s.cancelled) {
            "cancelled"
        } else if source.is_some_and(|s| s.errors > 0) {
            "completed_with_issues"
        } else if source.is_some() {
            "completed"
        } else {
            "idle"
        };
        let root_document = self.workspace.parked.get(&self.workspace.scope);
        let watch = if self.root == self.workspace.scope {
            if crate::platform::engine_watches() {
                self.native_watch_active
            } else {
                self.monitor.is_some()
            }
        } else {
            root_document.is_some_and(|doc| {
                if crate::platform::engine_watches() {
                    doc.native_watch_active
                } else {
                    doc.monitor.is_some()
                }
            })
        };
        let mut state = json!({"window_id":self.control_window_id,"phase":phase,"root":source.map(|s|&s.root),"scan_scope":self.workspace.scope,"focus_path":self.focus_path(),"focus":self.focus_path(),"selected_path":selected,"selection":selected,"scan_documents":documents,
            "snapshot_files":source.map(|s|s.files),"snapshot_folders":source.map(|s|s.folders),"snapshot_nodes":source.map(|s|s.nodes.len()),"files":source.map(|s|s.files),"folders":source.map(|s|s.folders),
        });
        let statistics = json!({"snapshot_logical_bytes":source.map(|s|s.nodes[0].logical),"snapshot_allocated_bytes":source.map(|s|s.nodes[0].allocated),"logical_bytes":source.map(|s|s.nodes[0].logical),"allocated_bytes":source.map(|s|s.nodes[0].allocated),
            "displayed_bytes":self.projection.as_ref().and_then(|p|p.weights.get(self.focus)),"projection_pending":self.projection_rx.is_some(),"geometry_pending":self.geometry.borrow().pending(),"snapshot_revision":self.control_revision(),
            "filter":self.filter_input.read(cx).value().to_string(),"expression":self.filter_input.read(cx).value().to_string(),"filter_error":self.filter_error,"status":self.status,"notice":self.status,"error":self.error_dialog,
        });
        let view = json!({"volume_traversal":source.and_then(|s|s.volume_traversal.clone()),"volume_total_bytes":source.map(|s|s.volume_total),"volume_free_bytes":source.map(|s|s.volume_free),"root_is_volume":source.map(|s|s.is_volume_root),
            "size_mode":if self.mode==crate::projection::SizeMode::Logical{"logical"}else{"allocated"},"show_hidden":self.hidden,"detail_depth":self.depth,"depth":self.depth,"list_mode":self.list_mode,
            "watching":self.watching,"watch_requested":self.watching,"watch_active":watch,"offline":self.offline,"cancelled":source.is_some_and(|s|s.cancelled),"issue_count":source.map(|s|s.errors),
        });
        let history = json!({"history_count":self.history.len(),"can_back":!self.history.is_empty(),"can_forward":!self.future.is_empty(),"breadcrumbs":self.breadcrumb_paths(),"coverage_percentage_available":false,
            "progress":self.progress.as_ref().map(|p|json!({"current_path":p.current,"files":p.files,"folders":p.folders,"pending_folders":p.pending,"issues":p.errors,"logical_bytes":p.logical,"allocated_bytes":p.allocated}))});
        for section in [statistics, view, history] {
            if let Some(values) = section.as_object() {
                state.as_object_mut().unwrap().extend(values.clone());
            }
        }
        state
    }
}
