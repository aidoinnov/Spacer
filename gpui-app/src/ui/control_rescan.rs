//! Scoped refresh commands resolve a live document without navigating the view.
use super::{app::Explorer, scan_document::ScanDocument};
use crate::{model::Snapshot, platform};
use gpui_kit::Context;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{collections::HashSet, path::PathBuf};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    path: Option<PathBuf>,
    #[serde(rename = "window_id")]
    _window_id: Option<String>,
}
impl Request {
    fn parse(args: &Value) -> anyhow::Result<Self> {
        let request: Self = serde_json::from_value(args.clone())
            .map_err(|_| anyhow::anyhow!("invalid_argument"))?;
        anyhow::ensure!(
            !args.get("path").is_some_and(Value::is_null)
                && request.path.as_ref().is_none_or(|p| p.is_absolute()),
            "invalid_argument"
        );
        Ok(request)
    }
}

fn validate_folder(source: &Snapshot, path: &str) -> anyhow::Result<()> {
    let id = source
        .node_at_path(path)
        .ok_or_else(|| anyhow::anyhow!("not_found"))?;
    anyhow::ensure!(source.nodes[id].directory, "not_directory");
    anyhow::ensure!(!source.nodes[id].boundary, "unsupported_scope");
    Ok(())
}

/// JSON string framing preserves line breaks in legitimate Unix filenames.
pub(super) fn command(root: &std::path::Path, path: &std::path::Path) -> String {
    if root == path {
        "rescan".into()
    } else {
        format!(
            "focus-json {}",
            serde_json::to_string(&path.to_string_lossy()).unwrap()
        )
    }
}

fn begin_parked(document: &mut ScanDocument, command: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!document.offline, "offline_document");
    anyhow::ensure!(!document.scanning, "scan_active");
    let session = document
        .session
        .as_ref()
        .filter(|s| s.is_alive())
        .ok_or_else(|| anyhow::anyhow!("engine_unavailable"))?;
    session.send(command);
    document.scanning = true;
    document.progress = None;
    document.status = "다시 분석 중".into();
    Ok(())
}

pub(super) fn apply(
    app: &mut Explorer,
    args: &Value,
    cx: &mut Context<Explorer>,
) -> anyhow::Result<Value> {
    let request = Request::parse(args)?;
    let path = request
        .path
        .map(|p| platform::scan_path(&p))
        .unwrap_or_else(|| app.workspace.scope.clone());
    anyhow::ensure!(
        crate::navigation::contains(&app.workspace.scope, &path),
        "outside_scope"
    );
    let mut seen = HashSet::new();
    let roots = [app.workspace.scope.clone(), app.root.clone()]
        .into_iter()
        .chain(app.workspace.parked.keys().cloned())
        .filter(|p| seen.insert(p.clone()));
    let mut target = None;
    for root in roots {
        let source = if root == app.root {
            app.snapshot.as_ref()
        } else {
            app.workspace
                .parked
                .get(&root)
                .and_then(|d| d.snapshot.as_ref())
        };
        if let Some(source) = source
            && source.node_at_path(&path.to_string_lossy()).is_some()
        {
            validate_folder(source, &path.to_string_lossy())?;
            target = Some((
                root,
                source
                    .document
                    .as_ref()
                    .map(|d| d.version.clone())
                    .or_else(|| source.wire_version.clone()),
            ));
            break;
        }
    }
    let (root, previous_version) = target.ok_or_else(|| anyhow::anyhow!("not_found"))?;
    let command = command(&root, &path);
    let background = root != app.root;
    if background {
        begin_parked(app.workspace.parked.get_mut(&root).unwrap(), &command)?;
    } else {
        anyhow::ensure!(!app.offline, "offline_document");
        anyhow::ensure!(!app.scanning, "scan_active");
        let session = app
            .session
            .as_ref()
            .filter(|s| s.is_alive())
            .ok_or_else(|| anyhow::anyhow!("engine_unavailable"))?;
        session.send(&command);
        app.scanning = true;
        app.progress = None;
        app.status = "다시 분석 중".into();
    }
    cx.notify();
    let full_root = root == path || platform::focused_rescan_scope() == "root";
    Ok(
        json!({"accepted":true,"requested_path":path,"document_root":root,
        "effective_path":if full_root {root} else {path},
        "scope_mode":if full_root {"root"} else {"subtree"},
        "background":background,"previous_version":previous_version}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn paths_are_framed_as_data_and_root_does_not_become_a_focus_command() {
        let root = std::env::temp_dir();
        let path = root.join("folder\nquit\r한글");
        let line = command(&root, &path);
        assert!(!line.contains(['\n', '\r']));
        let decoded: String =
            serde_json::from_str(line.strip_prefix("focus-json ").unwrap()).unwrap();
        assert_eq!(decoded, path.to_string_lossy());
        assert_eq!(command(&root, &root), "rescan");
    }
    #[test]
    fn invalid_request_is_rejected_before_dispatch() {
        for args in [
            json!({"path":"relative"}),
            json!({"path":true}),
            json!({"path":null}),
            json!({"focused":true}),
        ] {
            assert!(Request::parse(&args).is_err());
        }
        assert!(Request::parse(&json!({})).is_ok());
    }
    #[test]
    fn cached_scope_rejects_files_boundaries_and_prefix_siblings() {
        let source: Snapshot = serde_json::from_value(json!({"schema":1,"root":"/qa","cancelled":false,"files":1,"folders":3,"errors":0,"excluded":0,"elapsedSeconds":0,
            "nodes":[{"id":0,"name":"qa","path":"/qa","directory":true,"logical":1,"allocated":1,"children":[1,2,3]},
            {"id":1,"parent":0,"name":"folder","path":"/qa/folder","directory":true,"logical":0,"allocated":0},
            {"id":2,"parent":0,"name":"file","path":"/qa/file","directory":false,"logical":1,"allocated":1},
            {"id":3,"parent":0,"name":"boundary","path":"/qa/boundary","directory":true,"boundary":true,"logical":0,"allocated":0}]})).unwrap();
        assert!(validate_folder(&source, "/qa/folder").is_ok());
        for path in ["/qa/file", "/qa/boundary", "/qa-other", "/qa/missing"] {
            assert!(validate_folder(&source, path).is_err());
        }
    }
}
