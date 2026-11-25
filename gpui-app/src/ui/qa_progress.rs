//! Render current-version progress without a completed snapshot or a visible window.
use super::app::Explorer;
use gpui_kit::*;
use std::path::PathBuf;

pub fn run(handle: WindowHandle<Explorer>, output: PathBuf, cx: &mut App) {
    cx.defer(move |cx| {
        let result = AnyWindowHandle::from(handle)
            .update(cx, |root, window, cx| -> anyhow::Result<serde_json::Value> {
                let app = root.downcast::<Explorer>().map_err(|_| anyhow::anyhow!("wrong view"))?;
                let roots: Vec<_> = (0..8).map(|i| serde_json::json!({
                    "name": format!("Folder {i}"), "path": format!("/scan/folder-{i}"),
                    "directory": true, "logical": 8192, "allocated": 33554432
                })).collect();
                let progress: crate::model::Progress = serde_json::from_value(serde_json::json!({
                    "current":"/scan/folder-7", "files":65536, "folders":9, "pending":1,
                    "errors":0, "excluded":0, "logical":65536, "allocated":268435456,
                    "overviewVersion":crate::model::OVERVIEW_VERSION, "rootFolderCount":8,
                    "roots":roots
                }))?;
                progress.validate_overview()?;
                app.update(cx, |app, cx| {
                    app.scanning = true;
                    app.progress = Some(progress);
                    cx.notify();
                });
                super::frame::draw(window, cx);
                let (scanning, has_snapshot, rectangles, interactive) = app.read_with(cx, |app, _| (
                    app.scanning, app.snapshot.is_some(), app.tiles.borrow().len(),
                    app.tiles.borrow().iter().all(|t| t.interactive),
                ));
                anyhow::ensure!(scanning && !has_snapshot && rectangles == 8 && interactive,
                    "eight known root folders did not render without a snapshot");
                let image = window.render_to_image()?;
                anyhow::ensure!(image.width() >= 1000 && image.height() >= 600,
                    "renderer returned an unusable {}x{} capture", image.width(), image.height());
                image.save(output.with_extension("png"))?;
                Ok(serde_json::json!({
                    "passed":true, "scenario":"eight current root folders; hidden scripted GPUI render",
                    "scanning":scanning, "hasSnapshot":has_snapshot, "rectangles":rectangles,
                    "allInteractive":interactive, "width":image.width(), "height":image.height()
                }))
            }).and_then(|r| r);
        let report = match result {
            Ok(v) => v,
            Err(e) => serde_json::json!({"passed":false,"error":e.to_string()}),
        };
        let _ = std::fs::write(output, serde_json::to_vec_pretty(&report).unwrap());
        cx.quit();
    });
}
