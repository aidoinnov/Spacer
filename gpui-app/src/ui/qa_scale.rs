//! Actual renderer/IPC scale gate. Inputs are owned synthetic SNS documents.
use super::app::{Command, Explorer};
use gpui_kit::*;
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
async fn ready(handle: WindowHandle<Explorer>, cx: &mut AsyncApp) -> anyhow::Result<()> {
    let start = Instant::now();
    loop {
        let ready = AnyWindowHandle::from(handle).update(
            cx,
            |root, window, cx| -> anyhow::Result<bool> {
                let app = root
                    .downcast::<Explorer>()
                    .map_err(|_| anyhow::anyhow!("view"))?;
                super::frame::draw(window, cx);
                Ok(app.read_with(cx, |app, _| {
                    app.snapshot.is_some()
                        && app.projection.is_some()
                        && app.projection_rx.is_none()
                        && !app.geometry.borrow().pending()
                        && (app
                            .projection
                            .as_ref()
                            .is_some_and(|p| p.children.is_empty())
                            || app.tiles.borrow().iter().any(|t| t.opacity > 0.5))
                }))
            },
        )??;
        if ready {
            return Ok(());
        }
        anyhow::ensure!(
            start.elapsed() < Duration::from_secs(120),
            "scale readiness timeout"
        );
        cx.background_executor()
            .timer(Duration::from_millis(30))
            .await;
    }
}
pub fn run(handle: WindowHandle<Explorer>, output: PathBuf, cx: &mut App) {
    cx.spawn(async move|cx| {
        let result=async {
            let started=Instant::now();ready(handle,cx).await?;let first=started.elapsed().as_millis();
            let (files,nodes,child)=handle.read_with(cx,|app,_|{let source=app.snapshot.as_ref().unwrap();(source.files,source.nodes.len(),source.nodes[0].children.iter().copied().find(|&id|source.nodes[id].directory))})?;
            anyhow::ensure!(files>=1000,"scale fixture too small");
            if let Some(child)=child {AnyWindowHandle::from(handle).update(cx,|root,window,cx| {root.downcast::<Explorer>().unwrap().update(cx,|app,cx|app.command(Command::Navigate(child),window,cx));})?;ready(handle,cx).await?;}
            let mut samples=Vec::new();
            for expression in ["*.bin",":green","|*.bin","","*.bin"] {
                let start=Instant::now();AnyWindowHandle::from(handle).update(cx,|root,window,cx| {root.downcast::<Explorer>().unwrap().update(cx,|app,cx|{app.filter_input.update(cx,|input,cx|input.set_value(expression,window,cx));app.command(Command::Filter,window,cx);});})?;
                ready(handle,cx).await?;samples.push(start.elapsed().as_millis());
            }
            let before=handle.read_with(cx,|app,_|app.projection_work.statistics())?;
            let burst=Instant::now();AnyWindowHandle::from(handle).update(cx,|root,window,cx| {root.downcast::<Explorer>().unwrap().update(cx,|app,cx|{
                for index in 0..200 {app.filter_input.update(cx,|input,cx|input.set_value(if index%2==0{"|*.bin"}else{"*.bin"},window,cx));app.command(Command::Filter,window,cx);}
            });})?;
            ready(handle,cx).await?;let burst_ms=burst.elapsed().as_millis();
            let after=handle.read_with(cx,|app,_|app.projection_work.statistics())?;
            anyhow::ensure!(after.peak_active==1&&after.coalesced>before.coalesced,"projection queue did not coalesce");
            let mut resize=Vec::new();
            for (width,height) in [(1200.,760.),(1400.,900.),(1340.,860.)] {
                let start=Instant::now();AnyWindowHandle::from(handle).update(cx,|_,window,_|window.resize(size(px(width),px(height))))?;
                cx.background_executor().timer(Duration::from_millis(60)).await;
                ready(handle,cx).await?;resize.push(start.elapsed().as_millis());
            }
            let (tiles,remainder)=handle.read_with(cx,|app,_|{let tiles=app.tiles.borrow();(tiles.len(),tiles.iter().filter(|t|t.id.is_none()&&!t.interactive).count())})?;
            anyhow::ensure!(tiles>0,"blank large-folder map");
            let png=output.with_extension("png");AnyWindowHandle::from(handle).update(cx,|_,window,cx|->anyhow::Result<()> {super::frame::draw(window, cx);window.render_to_image()?.save(png)?;Ok(())})??;
            Ok::<_,anyhow::Error>(serde_json::json!({"passed":true,"files":files,"nodes":nodes,"firstReadyMs":first,"filterMs":samples,"burst200Ms":burst_ms,"coalescedDuringBurst":after.coalesced-before.coalesced,"startedDuringBurst":after.started-before.started,"projection":after,"resizeMs":resize,"tiles":tiles,"remainderTiles":remainder,"process":crate::platform::resources()}))
        }.await;
        let report=match result{Ok(value)=>value,Err(error)=>serde_json::json!({"passed":false,"error":error.to_string()})};
        let _=std::fs::write(output,serde_json::to_vec_pretty(&report).unwrap());cx.update(|cx|cx.quit());
    }).detach();
}
