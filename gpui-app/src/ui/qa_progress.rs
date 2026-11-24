//! Render a scripted progress message with no completed snapshot and no visible test window.
use super::app::Explorer;
use gpui_kit::*;
use std::path::PathBuf;
pub fn run(handle: WindowHandle<Explorer>, output: PathBuf, cx: &mut App) {
    cx.defer(move|cx|{
  let result=AnyWindowHandle::from(handle).update(cx,|root,window,cx|->anyhow::Result<serde_json::Value>{
   let app=root.downcast::<Explorer>().map_err(|_|anyhow::anyhow!("wrong view"))?;
   let progress:crate::model::Progress=serde_json::from_value(serde_json::json!({"current":"/scan/Code/branch","files":100000,"folders":30000,"pending":92,"errors":0,"excluded":0,"logical":200000000000u64,"allocated":249500000000u64,"roots":[{"name":"Code","path":"/scan/Code","directory":true,"logical":150000000000u64,"allocated":177900000000u64},{"name":"Media","path":"/scan/Media","directory":true,"logical":7000000000u64,"allocated":7900000000u64},{"name":"Data","path":"/scan/Data","directory":true,"logical":6000000000u64,"allocated":7000000000u64},{"name":"cache.sqlite","path":"/scan/Code/cache.sqlite","directory":false,"logical":2800000000u64,"allocated":2800000000u64}]}))?;
   app.update(cx,|app,cx|{app.scanning=true;app.progress=Some(progress);cx.notify();});
   super::frame::draw(window, cx);
   let (scanning,has_snapshot,rectangles,interactive)=app.read_with(cx,|app,_|(app.scanning,app.snapshot.is_some(),app.tiles.borrow().len(),app.tiles.borrow().iter().any(|t|t.interactive)));
   anyhow::ensure!(scanning&&!has_snapshot&&rectangles==4&&interactive,"progress map did not render without a snapshot");
   let image=window.render_to_image()?;anyhow::ensure!(image.width()>=1000&&image.height()>=600,"renderer returned an unusable {}x{} capture",image.width(),image.height());image.save(output.with_extension("png"))?;
   Ok(serde_json::json!({"passed":true,"scenario":"scripted progress IPC message; hidden GPUI render","scanning":scanning,"hasSnapshot":has_snapshot,"rectangles":rectangles,"interactive":interactive,"width":image.width(),"height":image.height()}))
  }).and_then(|r|r);
  let report=match result{Ok(v)=>v,Err(e)=>serde_json::json!({"passed":false,"error":e.to_string()})};
  let _=std::fs::write(output,serde_json::to_vec_pretty(&report).unwrap());cx.quit();
 });
}
