//! Owned nested mounts: verify the common UI command starts a fresh scoped document.
use super::app::{Command, Explorer};
use gpui_kit::*;
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
pub fn run(handle: WindowHandle<Explorer>, output: PathBuf, cx: &mut App) {
    cx.spawn(async move|cx| {
        let result=async {
            anyhow::ensure!(crate::platform::mounted_volumes_supported(),"mounted-volume adapter unavailable");
            let mut checks=Vec::new();
            for (include,files,excluded) in [(false,100,1),(true,6100,0),(false,100,1)] {
                let start=Instant::now();
                loop {
                    let ready=handle.read_with(cx,|app,_|!app.scanning&&app.projection_rx.is_none()&&app.snapshot.is_some())?;
                    if ready {break;}
                    anyhow::ensure!(start.elapsed()<Duration::from_secs(30),"scope result timeout");
                    cx.background_executor().timer(Duration::from_millis(50)).await;
                }
                let state=handle.read_with(cx,|app,_|{
                    let snapshot=app.snapshot.as_ref().unwrap();
                    (app.include_mounted,snapshot.files,snapshot.excluded,snapshot.volume_traversal.clone(),app.root.clone())
                })?;
                anyhow::ensure!(state.0==include&&state.1==files&&state.2==excluded,"wrong scope state: {state:?}");
                anyhow::ensure!(state.3.as_deref()==Some(if include {"allVolumes"} else {"selectedVolume"}),"scope provenance");
                checks.push(serde_json::json!({"includeMounted":include,"files":files,"excluded":excluded,"elapsedMs":start.elapsed().as_millis()}));
                if checks.len()<3 {
                    AnyWindowHandle::from(handle).update(cx,|root,window,cx|->anyhow::Result<()> {
                        let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
                        if include {super::frame::draw(window, cx);window.render_to_image()?.save(output.with_extension("png"))?;}
                        app.update(cx,|app,cx|app.command(Command::MountedVolumes,window,cx));Ok(())
                    })??;
                }
            }
            Ok::<_,anyhow::Error>(serde_json::json!({"passed":true,"checks":checks,"rootRestarted":true,"commonUICommand":true}))
        }.await;
        let report=match result {Ok(value)=>value,Err(error)=>serde_json::json!({"passed":false,"error":error.to_string()})};
        let _=std::fs::write(output,serde_json::to_vec_pretty(&report).unwrap());cx.update(|cx|cx.quit());
    }).detach();
}
