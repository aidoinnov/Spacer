//! GPUI command/state acceptance with real native processes and owned artifacts.
use super::app::{Command, Explorer};
use crate::{
    backend::{Event, ScanSession},
    document,
    model::Snapshot,
    platform,
};
use gpui_kit::*;
use std::{
    io::{Seek, Write},
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

struct Roundtrip {
    _directory: tempfile::TempDir,
    multiple: PathBuf,
    snapshot: Arc<Snapshot>,
    session: ScanSession,
}
fn roundtrip(
    source: Arc<Snapshot>,
    tags: std::collections::HashMap<String, u8>,
) -> anyhow::Result<Roundtrip> {
    let directory = tempfile::tempdir()?;
    let sns = directory.path().join("saved.sns");
    let report = directory.path().join("files.txt");
    let native = source.document.as_ref().unwrap();
    document::save_atomic(
        native,
        serde_json::json!({"operation":"sns","tags":tags}),
        &sns,
    )?;
    document::save_atomic(
        native,
        serde_json::json!({"operation":"report","filter":":green","tags":tags}),
        &report,
    )?;
    let text = std::fs::read_to_string(report)?;
    anyhow::ensure!(
        !text.is_empty() && !text.contains('\t'),
        "native TXT format"
    );
    let multiple = directory.path().join("multiple.sns");
    let mut output = std::fs::File::create(&multiple)?;
    let mut input = std::fs::File::open(&sns)?;
    std::io::copy(&mut input, &mut output)?;
    input.rewind()?;
    std::io::copy(&mut input, &mut output)?;
    output.flush()?;
    let session = ScanSession::open(&platform::backend(), &sns)?;
    loop {
        match session.events.recv_timeout(Duration::from_secs(30))? {
            Event::Complete(snapshot) => {
                anyhow::ensure!(snapshot.tags == tags, "SNS tags lost");
                return Ok(Roundtrip {
                    _directory: directory,
                    multiple,
                    snapshot,
                    session,
                });
            }
            Event::Failure(error) => anyhow::bail!(error),
            _ => {}
        }
    }
}
pub fn run(handle: WindowHandle<Explorer>, output: PathBuf, cx: &mut App) {
    cx.spawn(async move |cx| {
        let result = async {
            let started=Instant::now();
            loop {
                if handle.read_with(cx,|app,_|!app.scanning&&app.projection.is_some())? {break;}
                anyhow::ensure!(started.elapsed()<Duration::from_secs(30),"native scan/projection timeout");
                cx.background_executor().timer(Duration::from_millis(50)).await;
            }
            let source=AnyWindowHandle::from(handle).update(cx,|root,window,cx| -> anyhow::Result<_> {
                let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                let (source,branch,file)=app.update(cx,|app,cx| -> anyhow::Result<_> {
                    let source=app.snapshot.clone().unwrap();
                    anyhow::ensure!(source.document.is_some(),"native semantic document missing");
                    let branch=source.nodes.iter().find(|n|n.name=="branch"&&n.directory)
                        .ok_or_else(||anyhow::anyhow!("fixture needs branch"))?;
                    let file=branch.children.iter().copied().find(|&id|!source.nodes[id].directory)
                        .ok_or_else(||anyhow::anyhow!("branch file missing"))?;
                    let branch=branch.id;
                    window.focus(&app.focus_handle,cx);
                    app.command(Command::Select(file),window,cx);
                    Ok((source,branch,file))
                })?;
                super::frame::draw(window, cx);
                window.dispatch_keystroke(Keystroke::parse("enter")?,cx);
                anyhow::ensure!(app.read_with(cx,|app,_|app.focus==branch),"Return must zoom file's containing folder");
                app.update(cx,|app,cx|{
                    app.command(Command::Back,window,cx);
                    app.command(Command::Select(file),window,cx);
                });
                if platform::preview_supported() {
                    window.dispatch_keystroke(Keystroke::parse("space")?,cx);
                    anyhow::ensure!(!app.read_with(cx,|app,_|app.status.starts_with("미리보기 오류")),"native Quick Look failed");
                }
                app.update(cx,|app,cx| -> anyhow::Result<()> {
                    app.command(Command::Select(branch),window,cx);
                    app.command(Command::Tag(3),window,cx);
                    anyhow::ensure!(app.tag_for(branch)==4&&app.tag_for(file)==0,"own tag display / bitmask");
                    app.filter_input.update(cx,|input,cx|input.set_value(":green",window,cx));
                    app.command(Command::Filter,window,cx);
                    Ok(())
                })?;
                Ok(source)
            })??;
            if platform::preview_supported() {
                let deadline=Instant::now();
                while !platform::preview_observation().is_some_and(|p|p.visible) {
                    anyhow::ensure!(deadline.elapsed()<Duration::from_secs(12),"preview did not become visible");
                    cx.background_executor().timer(Duration::from_millis(50)).await;
                }
            }
            loop {
                if handle.read_with(cx,|app,_|app.projection_rx.is_none())? {break;}
                anyhow::ensure!(started.elapsed()<Duration::from_secs(30),"tag projection timeout");
                cx.background_executor().timer(Duration::from_millis(25)).await;
            }
            let tags=handle.read_with(cx,|app,_|app.tags.clone())?;
            anyhow::ensure!(handle.read_with(cx,|app,_|app.projection.as_ref().is_some_and(|p|p.weights[0]>0))?,"tag filter");
            let restored=cx.background_executor().spawn(async move {roundtrip(source,tags)}).await?;
            let multiple=restored.multiple.clone();
            AnyWindowHandle::from(handle).update(cx,|root,window,cx| -> anyhow::Result<()> {
                let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                app.update(cx,|app,cx|app.install_snapshot(restored.snapshot,Some(restored.session),window,cx));
                Ok(())
            })??;
            // First cancel a multi-root open: the current document must survive.
            let before=handle.read_with(cx,|app,_|app.snapshot.clone().unwrap())?;
            for cancel in [true,false] {
                AnyWindowHandle::from(handle).update(cx,|root,window,cx| -> anyhow::Result<()> {
                    let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                    app.update(cx,|app,cx|app.open_snapshot_file(multiple.clone(),window,cx));Ok(())
                })??;
                loop {
                    if handle.read_with(cx,|app,_|app.document_choice.is_some())? {break;}
                    anyhow::ensure!(started.elapsed()<Duration::from_secs(30),"multi-root choice timeout");
                    cx.background_executor().timer(Duration::from_millis(25)).await;
                }
                AnyWindowHandle::from(handle).update(cx,|root,window,cx| -> anyhow::Result<()> {
                    let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                    app.update(cx,|app,cx| {
                        anyhow::ensure!(Arc::ptr_eq(app.snapshot.as_ref().unwrap(),&before),"open replaced document before selection");
                        app.command(Command::ChooseDocument(if cancel {None}else{Some(1)}),window,cx);
                        anyhow::Ok(())
                    })
                })??;
                if cancel {
                    anyhow::ensure!(handle.read_with(cx,|app,_|app.pending_import.is_none()&&Arc::ptr_eq(app.snapshot.as_ref().unwrap(),&before))?,"cancel changed current document");
                } else {
                    loop {
                        if handle.read_with(cx,|app,_|app.pending_import.is_none()&&app.projection_rx.is_none())? {break;}
                        anyhow::ensure!(started.elapsed()<Duration::from_secs(30),"selected SNS import timeout");
                        cx.background_executor().timer(Duration::from_millis(25)).await;
                    }
                }
            }
            AnyWindowHandle::from(handle).update(cx,|root,window,cx| -> anyhow::Result<()> {
                let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                app.update(cx,|app,cx| {
                    anyhow::ensure!(app.offline&&app.filter_input.read(cx).value().is_empty(),"SNS load must reset filter");
                    app.filter_input.update(cx,|input,cx|input.set_value("*.no-matching-extension",window,cx));
                    app.command(Command::Filter,window,cx);anyhow::Ok(())
                })
            })??;
            loop {
                if handle.read_with(cx,|app,_|app.projection_rx.is_none())? {break;}
                anyhow::ensure!(started.elapsed()<Duration::from_secs(30),"empty filter timeout");
                cx.background_executor().timer(Duration::from_millis(25)).await;
            }
            AnyWindowHandle::from(handle).update(cx,|root,window,cx| -> anyhow::Result<()> {
                let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                app.update(cx,|app,cx| {
                    anyhow::ensure!(app.projection.as_ref().is_some_and(|p|p.weights[0]==0),"zero-result filter");
                    app.command(Command::ClearFilter,window,cx);anyhow::Ok(())
                })
            })??;
            loop {
                if handle.read_with(cx,|app,_|app.projection_rx.is_none())? {break;}
                anyhow::ensure!(started.elapsed()<Duration::from_secs(30),"clear filter timeout");
                cx.background_executor().timer(Duration::from_millis(25)).await;
            }
            AnyWindowHandle::from(handle).update(cx,|root,window,cx| -> anyhow::Result<()> {
                let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                anyhow::ensure!(app.read_with(cx,|app,_|app.projection.as_ref().is_some_and(|p|p.weights[0]>0)),"clear filter reprojection");
                super::frame::draw(window, cx);let image=window.render_to_image()?;
                anyhow::ensure!(image.width()>=1000&&image.height()>=600,"invalid capture");
                image.save(output.with_extension("png"))?;Ok(())
            })??;
            drop(restored._directory);
            Ok::<_,anyhow::Error>(serde_json::json!({"passed":true,"nativeProjection":true,
                "returnKeyZoom":true,"nativePreview":platform::preview_supported(),"previewObservation":platform::preview_observation(),"ownTagBitmask":true,
                "ancestorTagFilter":true,"binarySNSAtomicSaveAndReopen":true,"nativeReport":true,
                "explicitMultiRootChoice":true,"cancelPreservesDocument":true,"offlineReprojection":true,
                "emptyFilterAndClear":true,"elapsedMs":started.elapsed().as_millis()}))
        }.await;
        let report=match result {Ok(value)=>value,Err(error)=>serde_json::json!({"passed":false,"error":error.to_string()})};
        let _=std::fs::write(output,serde_json::to_vec_pretty(&report).unwrap());cx.update(|cx|cx.quit());
    }).detach();
}
