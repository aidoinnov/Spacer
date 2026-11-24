//! Exercises the real treemap mouse handlers, then history, with native scan processes.
use super::app::{Command, Explorer};
use gpui_kit::*;
use std::{path::PathBuf, time::Duration};
pub fn run(handle: WindowHandle<Explorer>, output: PathBuf, cx: &mut App) {
    cx.set_reduce_motion(true);
    cx.spawn(async move|cx|{
  let result:anyhow::Result<serde_json::Value>=async{
   cx.background_executor().timer(Duration::from_millis(100)).await;
   let (scope,branch,root_pid)=AnyWindowHandle::from(handle).update(cx,|root,window,cx|->anyhow::Result<_>{
    let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
    let(scope,pid)=app.read_with(cx,|app,_|(app.root.clone(),app.session.as_ref().unwrap().process_id()));let branch=scope.join("branch");anyhow::ensure!(branch.is_dir(),"fixture requires branch directory");
    let progress=crate::model::Progress{allocated:16384,logical:12345,roots:vec![crate::model::Overview{name:"branch".into(),path:branch.display().to_string(),directory:true,allocated:16384,logical:12345}],..Default::default()};
    let completed=app.update(cx,|app,cx|{let saved=app.snapshot.take();app.projection=None;app.progress=Some(progress);app.scanning=true;cx.notify();saved});super::frame::draw(window, cx);
    let position=app.read_with(cx,|app,_|{let tiles=app.tiles.borrow();let t=tiles.iter().find(|t|t.interactive&&t.folder).unwrap();point(px(t.rect.x+t.rect.w/2.),px(t.rect.y+t.rect.h/2.))});
    window.dispatch_event(PlatformInput::MouseDown(MouseDownEvent{button:MouseButton::Left,position,modifiers:Modifiers::default(),click_count:1,first_mouse:false}),cx);
    window.dispatch_event(PlatformInput::MouseUp(MouseUpEvent{button:MouseButton::Left,position,modifiers:Modifiers::default(),click_count:1}),cx);
    let clicked=app.read_with(cx,|app,_|app.root.clone());anyhow::ensure!(clicked==branch,"real mouse click did not enter branch: {}",clicked.display());
    if let Some(completed)=completed{app.update(cx,|app,_|{if let Some(root)=app.workspace.parked.get_mut(&scope){root.snapshot=Some(completed);root.scanning=false;}});}
    Ok((scope,branch,pid))
   })??;
   cx.background_executor().timer(Duration::from_millis(500)).await;
   let mut report=AnyWindowHandle::from(handle).update(cx,|root,window,cx|->anyhow::Result<_>{
    let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;
    let parked_pid=app.read_with(cx,|app,_|app.workspace.parked.get(&scope).and_then(|p|p.session.as_ref()).map(|s|s.process_id()));anyhow::ensure!(parked_pid==Some(root_pid),"original scan was replaced");
    super::frame::draw(window, cx);window.render_to_image()?.save(output.with_extension("png"))?;
    app.update(cx,|app,cx|app.command(Command::Back,window,cx));anyhow::ensure!(app.read_with(cx,|app,_|app.root==scope),"back");
    app.update(cx,|app,cx|app.command(Command::Forward,window,cx));anyhow::ensure!(app.read_with(cx,|app,_|app.root==branch),"forward");
    app.update(cx,|app,cx|app.command(Command::Up,window,cx));anyhow::ensure!(app.read_with(cx,|app,_|app.root==scope),"up");
    let final_pid=app.read_with(cx,|app,_|app.session.as_ref().map(|s|s.process_id()));anyhow::ensure!(final_pid==Some(root_pid),"root session changed on return");
    Ok(serde_json::json!({"passed":true,"realMouseClick":true,"snapshotRequired":false,"branch":branch,"back":true,"forward":true,"up":true,"originalScanPidBefore":root_pid,"originalScanPidAfter":final_pid}))
   })??;
   cx.background_executor().timer(Duration::from_millis(300)).await;
   AnyWindowHandle::from(handle).update(cx,|root,window,cx|->anyhow::Result<()>{
    let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("view"))?;super::frame::draw(window, cx);
    let position=app.read_with(cx,|app,_|{let tiles=app.tiles.borrow();tiles.iter().find(|t|t.folder&&t.id.is_some()&&std::path::Path::new(&t.path)==branch).map(|t|point(px(t.rect.x+12.),px(t.rect.y+10.)))}).ok_or_else(||anyhow::anyhow!("completed folder not painted"))?;
    window.dispatch_event(PlatformInput::MouseDown(MouseDownEvent{button:MouseButton::Left,position,modifiers:Modifiers::default(),click_count:1,first_mouse:false}),cx);window.dispatch_event(PlatformInput::MouseUp(MouseUpEvent{button:MouseButton::Left,position,modifiers:Modifiers::default(),click_count:1}),cx);
    anyhow::ensure!(app.read_with(cx,|app,_|app.focus_path()==branch),"completed map mouse click");app.update(cx,|app,cx|app.command(Command::Back,window,cx));anyhow::ensure!(app.read_with(cx,|app,_|app.focus_path()==scope),"completed map back");
    super::frame::draw(window, cx);
    let file_position=app.read_with(cx,|app,_|app.tiles.borrow().iter().find(|t|!t.folder&&t.id.is_some()&&std::path::Path::new(&t.path).starts_with(&branch)).map(|t|point(px(t.rect.x+t.rect.w/2.),px(t.rect.y+t.rect.h/2.)))).ok_or_else(||anyhow::anyhow!("nested file not painted"))?;
    for count in [1,2]{window.dispatch_event(PlatformInput::MouseDown(MouseDownEvent{button:MouseButton::Left,position:file_position,modifiers:Modifiers::default(),click_count:count,first_mouse:false}),cx);window.dispatch_event(PlatformInput::MouseUp(MouseUpEvent{button:MouseButton::Left,position:file_position,modifiers:Modifiers::default(),click_count:count}),cx);}
    anyhow::ensure!(app.read_with(cx,|app,_|app.focus_path()==branch),"file double click must zoom containing folder");
    app.update(cx,|app,cx|{app.scanning=true;app.progress=Some(crate::model::Progress{allocated:999999,logical:999999,..Default::default()});cx.notify();});super::frame::draw(window, cx);
    anyhow::ensure!(app.read_with(cx,|app,_|!app.uses_progress_map()&&app.tiles.borrow().iter().all(|t|t.id.is_some())),"root scan progress replaced the detail view");Ok(())
   })??;
   report["completedSnapshotMouseClick"]=true.into();report["fileDoubleClickContainingFolder"]=true.into();report["detailRetainedDuringRootProgress"]=true.into();Ok(report)
  }.await;
  let report=match result{Ok(v)=>v,Err(e)=>serde_json::json!({"passed":false,"error":e.to_string()})};let _=std::fs::write(output,serde_json::to_vec_pretty(&report).unwrap());cx.update(|cx|cx.quit());
 }).detach();
}
