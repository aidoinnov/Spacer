//! Main-thread window routing; native queries and artifacts run off the UI thread.
use super::{app::Command, windows};
use super::{
    control_jobs::{ImportResult, Jobs, Outcome},
    control_queries::prepare_query,
    control_state::{state_with_window, window_id},
};
use gpui_kit::*;
use serde_json::{Value, json};
use std::time::Duration;
pub fn install(cx: &mut App) {
    let server = match crate::automation::Server::start() {
        Ok(server) => server,
        Err(error) => {
            eprintln!("Local control unavailable: {error}");
            return;
        }
    };
    let shutdown = server.shutdown_handle();
    cx.on_app_quit(move |_| {
        shutdown.stop();
        async {}
    })
    .detach();
    cx.spawn(async move|cx| {
        let mut jobs=Jobs::new();
        loop {
            cx.background_executor().timer(Duration::from_millis(30)).await;
            while let Ok((id,outcome))=jobs.rx.try_recv(){
                let finished=match outcome {
                    Outcome::Value(value)=>Some(value),
                    Outcome::ImportStarted{window,generation,process}=>{cx.update(|cx| {
                        if let Some(handle)=windows::handles(cx).into_iter().find(|h|window_id(*h)==window) {
                            let _=handle.update(cx,|app,_,_| {if app.document_open_id==generation {app.pending_import=Some(process.clone());}else{process.shutdown();}});
                        }else{process.shutdown();}
                    });None},
                    Outcome::ImportFinished{window,generation,result}=>Some(cx.update(|cx| {
                        let handle=windows::handles(cx).into_iter().find(|h|window_id(*h)==window);
                        let Some(handle)=handle else{return json!({"job_id":id,"phase":"cancelled"})};
                        handle.update(cx,|app,window,cx| {
                            if app.document_open_id!=generation{return json!({"job_id":id,"phase":"cancelled"})}
                            app.pending_import=None;
                            match result {
                                Ok(ImportResult::Document(source,session))=>{app.install_snapshot(source,Some(session),window,cx);json!({"job_id":id,"phase":"completed","result":{"loaded":true,"projection_pending":true}})},
                                Ok(ImportResult::Inspection(value))=>json!({"job_id":id,"phase":"completed","result":value}),
                                Err(error)=>{app.error_dialog=Some(error.to_string());cx.notify();json!({"job_id":id,"phase":"failed","error":error.to_string()})}
                            }
                        }).unwrap_or_else(|_|json!({"job_id":id,"phase":"cancelled"}))
                    }))
                };
                if let Some(value)=finished {jobs.active=jobs.active.saturating_sub(1);if jobs.values.contains_key(&id){jobs.values.insert(id,value);}}
            }
            while let Ok(request)=server.try_recv() {
                let id=request.value["id"].clone();let command=request.value["command"].as_str().unwrap_or("");let args=&request.value["arguments"];
                if ["node_info","tree_children","query_nodes","largest_nodes","scan_issues"].contains(&command) {
                    let prepared=cx.update(|cx|prepare_query(command,args,cx));
                    match prepared {
                        Ok((native,command))=> {let reply=request.reply;std::thread::spawn(move|| {
                            let result=(||->anyhow::Result<Value>{let mut bytes=Vec::new();native.request(command,&mut bytes)?;Ok(serde_json::from_slice(&bytes)?)})();
                            let _=reply.send(rpc_response(id,result));
                        });},
                        Err(error)=>{let _=request.reply.send(rpc_response(id,Err(error)));}
                    }
                    continue;
                }
                let response=cx.update(|cx|execute(command,args,&mut jobs,cx));
                let response=rpc_response(id,response);
                let _=request.reply.send(response);
            }
        }
    }).detach();
}
fn rpc_response(id: Value, result: anyhow::Result<Value>) -> Value {
    match result {
        Ok(result) => json!({"id":id,"result":result}),
        Err(error) => {
            json!({"id":id,"error":{"code":error.to_string(),"message":error.to_string()}})
        }
    }
}
fn execute(command: &str, args: &Value, jobs: &mut Jobs, cx: &mut App) -> anyhow::Result<Value> {
    if command == "task_status" {
        return jobs
            .values
            .get(args["job_id"].as_str().unwrap_or(""))
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("not_found"));
    }
    if command == "window_new" {
        let handle = windows::open(None, cx)?;
        return Ok(json!({"window_id":window_id(handle)}));
    }
    let handles = windows::handles(cx);
    if command == "app_resources" {
        let workers:Vec<_>=handles.iter().filter_map(|h|h.read_with(cx,|app,_|json!({"window_id":app.control_window_id,"projection":app.projection_work.statistics(),"geometry":app.geometry.borrow().statistics()})).ok()).collect();
        return Ok(json!({"process":crate::platform::resources(),"workers":workers}));
    }
    if command == "volume_info" {
        return crate::platform::volume_info(&required_path(args, "path")?);
    }
    if command == "volumes_list" {
        let volumes:Vec<_>=handles.first().and_then(|h|h.read_with(cx,|app,_|app.volumes.clone()).ok()).unwrap_or_default().into_iter().map(|path|json!({"name":path.file_name().map(|s|s.to_string_lossy()).unwrap_or_default(),"path":path})).collect();
        return Ok(json!({"volumes":volumes}));
    }
    if command == "app_status" && args.get("window_id").is_none() {
        let states: Vec<_> = handles
            .iter()
            .filter_map(|h| {
                h.update(cx, |app, window, cx| state_with_window(app, window, cx))
                    .ok()
            })
            .collect();
        return Ok(
            json!({"pid":std::process::id(),"bundle_id":crate::automation::BUNDLE_ID,"version":env!("CARGO_PKG_VERSION"),"windows":states,"jobs":jobs.order.iter().filter_map(|id|jobs.values.get(id)).collect::<Vec<_>>() }),
        );
    }
    let handle = if let Some(id) = args["window_id"].as_str() {
        handles
            .into_iter()
            .find(|h| window_id(*h) == id)
            .ok_or_else(|| anyhow::anyhow!("not_found"))?
    } else {
        anyhow::ensure!(handles.len() == 1, "window_required");
        handles[0]
    };
    #[cfg(feature = "capture")]
    if command == "view_capture" {
        // Drawing updates the root entity. Do not hold its mutable lease here.
        return AnyWindowHandle::from(handle).update(cx, |_, window, cx| {
            super::frame::draw(window, cx);
            let image = window.render_to_image()?;
            let image = image::imageops::thumbnail(&image, 1600, 1200);
            use base64::Engine;
            let mut data = std::io::Cursor::new(Vec::new());
            image.write_to(&mut data, image::ImageFormat::Png)?;
            Ok(json!({"image":{"mimeType":"image/png","data":base64::engine::general_purpose::STANDARD.encode(data.into_inner())}}))
        })?;
    }
    handle.update(cx, |app, window, cx| -> anyhow::Result<Value> {
        match command {
            "app_status" => Ok(state_with_window(app, window, cx)),
            "window_close" => {
                window.remove_window();
                Ok(json!({"accepted":true}))
            }
            "scan_start" => super::control_scan::start(app, args, window, cx),
            "scan_stop" => {
                app.command(Command::Cancel, window, cx);
                Ok(json!({"accepted":true}))
            }
            "scan_rescan" => super::control_rescan::apply(app, args, cx),
            "view_set" => super::control_view::apply(app, args, window, cx),
            "node_tag" => {
                let path = required_path(args, "path")?;
                let id = app
                    .snapshot
                    .as_ref()
                    .and_then(|s| s.node_at_path(&path.to_string_lossy()))
                    .ok_or_else(|| anyhow::anyhow!("not_found"))?;
                let color = args["color"]
                    .as_u64()
                    .filter(|c| *c <= 4)
                    .ok_or_else(|| anyhow::anyhow!("invalid_argument"))?;
                app.tag_node(id, color as u8, cx);
                Ok(json!({"accepted":true}))
            }
            "report_export" | "snapshot_save" | "snapshot_load" => {
                super::control_artifacts::execute(command, args, jobs, app, cx)
            }
            _ => anyhow::bail!("unknown_command"),
        }
    })?
}
pub(super) fn required_path(args: &Value, key: &str) -> anyhow::Result<std::path::PathBuf> {
    let path = std::path::PathBuf::from(
        args[key]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("invalid_argument"))?,
    );
    anyhow::ensure!(path.is_absolute(), "invalid_argument");
    Ok(path)
}
