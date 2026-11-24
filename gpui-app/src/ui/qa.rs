//! Headful acceptance probe. Calls the same commands as buttons, after real paints.
use super::app::{Command, Explorer};
use gpui_kit::*;
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
pub fn install(
    this: &mut Explorer,
    output: PathBuf,
    window: &mut Window,
    cx: &mut Context<Explorer>,
) {
    let _ = this;
    cx.spawn_in(window,async move|this,cx|{
  let started=Instant::now();let mut stage=0;let mut changed=Instant::now();let mut checks=Vec::new();
  loop{cx.background_executor().timer(Duration::from_millis(50)).await;
   let result=this.update_in(cx,|app,window,cx|{
    if app.scanning||app.projection.is_none(){return false}
    if stage==0 && app.tiles.borrow().is_empty(){cx.notify();return false}
    if stage>0&&changed.elapsed()<Duration::from_millis(650){return false}
    let source=app.snapshot.as_ref().unwrap().clone();
    let name=match stage{
     0=>{assert!(window.is_visible());assert!(!app.tiles.borrow().is_empty());source.validate().unwrap();"native_scan_and_first_paint"},
     1=>{assert_ne!(app.focus,0);"navigate_and_transition"},
     2=>{assert_eq!(app.focus,0);"back"},
     3=>{assert_ne!(app.focus,0);"forward"},
     4=>{assert_eq!(app.focus,0);"up"},
     5=>{assert!(app.list_mode);"list_mode"},
     6=>{assert!(!app.list_mode);"treemap_mode"},
     7=>{assert_eq!(app.mode,crate::projection::SizeMode::Logical);"logical_size"},
     8=>{assert!(!app.hidden);"hidden_toggle"},
     9=>{assert!(app.filter_error.is_empty());let p=app.projection.as_ref().unwrap();for n in &source.nodes{if !n.directory&&p.weights[n.id]>0{assert!(n.name.ends_with(".zip"));}}"filter"},
     _=>return true,
    };
    checks.push(serde_json::json!({"name":name,"passed":true,"elapsedMs":started.elapsed().as_millis(),"tiles":app.tiles.borrow().len(),"focus":app.focus}));
    if matches!(stage,0|1|5)&& let Ok(image)=window.render_to_image(){let file=output.with_file_name(format!("gpui-stage-{stage}.png"));let _=image.save(file);}
    match stage{
     0=>{let id=source.nodes[0].children.iter().copied().find(|&i|source.nodes[i].directory&&source.nodes[i].allocated>0).expect("QA fixture needs nonempty folder");app.command(Command::Navigate(id),window,cx);},
     1=>app.command(Command::Back,window,cx),2=>app.command(Command::Forward,window,cx),3=>app.command(Command::Up,window,cx),
     4|5=>app.command(Command::List,window,cx),6=>app.command(Command::Logical,window,cx),7=>app.command(Command::Hidden,window,cx),
     8=>{app.filter_input.update(cx,|input,cx|input.set_value("*.zip",window,cx));app.command(Command::Filter,window,cx)},
     9=>{app.filter_input.update(cx,|input,cx|input.set_value("",window,cx));app.command(Command::Filter,window,cx);},_=>{}
    }stage+=1;changed=Instant::now();false
   });
   let done=match result{Ok(done)=>done,Err(_)=>break};
   if done||started.elapsed()>Duration::from_secs(60){let report=serde_json::json!({"passed":done,"checks":checks,"elapsedMs":started.elapsed().as_millis(),"framework":"GPUI","engine":"existing Swift engine"});let _=std::fs::write(&output,serde_json::to_vec_pretty(&report).unwrap());break}
  }
 }).detach();
}
