#![allow(unsafe_code, reason = "SDK proc_pid_rusage with a sized owned output buffer")]
// macOS scan-boundary RSS probe; shipped scanner source is unchanged.
use std::{hint::black_box, path::Path, time::Instant};
use disktree_core::scan::{scan, ScanOptions};
use disktree_core::scan_threads::ScanThreads;
#[repr(C)]
#[derive(Default)]
struct Usage { uuid: [u8; 16], values: [u64; 18] }
unsafe extern "C" { fn proc_pid_rusage(pid: i32, flavor: i32, buffer: *mut Usage) -> i32; }
fn memory() -> Usage {
    assert_eq!(std::mem::size_of::<Usage>(), 160);
    let mut usage = Usage::default();
    // SDK sys/resource.h rusage_info_v2: uuid + 18 uint64_t fields.
    // indices 6/7 are resident_size/phys_footprint, in bytes.
    assert_eq!(unsafe { proc_pid_rusage(std::process::id() as i32, 2, &mut usage) }, 0);
    usage
}
fn main() {
 let args:Vec<String> = std::env::args().collect();
 let workers:usize=args[2].parse().unwrap();
 let options=ScanOptions{dedup_hardlinks:false,threads:ScanThreads{max_threads:workers,adaptive:false,system_cpu_limit:None,..ScanThreads::default()},..ScanOptions::default()};
 let before=memory(); let start=Instant::now();
 let node=scan(Path::new(&args[1]),options).unwrap();
 let ms=start.elapsed().as_secs_f64()*1000.;
 black_box(&node);
 let after=memory();
 println!("{{\"ms\":{},\"files\":{},\"dirs\":{},\"bytes\":{},\"workers\":{},\"rss_before_bytes\":{},\"rss_after_scan_bytes\":{},\"footprint_after_scan_bytes\":{}}}",ms,node.files,node.dirs,node.bytes,workers,before.values[6],after.values[6],after.values[7]);
 black_box(node);
}
