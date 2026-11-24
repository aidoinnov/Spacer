//! Native query handoff, independent of transport and artifact jobs.
use super::{control_state::window_id, windows};
use gpui_kit::*;
use serde_json::Value;
pub(super) fn prepare_query(
    command: &str,
    args: &Value,
    cx: &mut App,
) -> anyhow::Result<(crate::document::NativeDocument, Value)> {
    let handles = windows::handles(cx);
    let handle = if let Some(id) = args["window_id"].as_str() {
        handles
            .into_iter()
            .find(|h| window_id(*h) == id)
            .ok_or_else(|| anyhow::anyhow!("not_found"))?
    } else {
        anyhow::ensure!(handles.len() == 1, "window_required");
        handles[0]
    };
    handle.read_with(cx, |app, cx| {
        anyhow::ensure!(app.projection_rx.is_none(), "projection_pending");
        let native = app
            .snapshot
            .as_ref()
            .and_then(|s| s.document.clone())
            .ok_or_else(|| anyhow::anyhow!("no_native_document"))?;
        let mut request = app.document_command(cx);
        request["operation"] = "query".into();
        request["query"] = command.into();
        request["arguments"] = args.clone();
        Ok((native, request))
    })?
}
