use std::path::Path;
pub fn focused_rescan_scope() -> &'static str {
    "subtree"
}
pub fn applications() -> std::path::PathBuf {
    "/Applications".into()
}
pub fn volumes() -> Vec<std::path::PathBuf> {
    let mut paths = vec![std::path::PathBuf::from("/")];
    if let Ok(entries) = std::fs::read_dir("/Volumes") {
        paths.extend(entries.filter_map(Result::ok).map(|e| e.path()));
    }
    paths
}

pub fn reveal_label() -> &'static str {
    "Finder에서 보기"
}


/// Loads the original AppKit QuickLook owner into GPUI's existing NSApplication.
static PREVIEW_VISIBLE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
fn preview_library() -> anyhow::Result<&'static libloading::Library> {
    static LIBRARY: std::sync::OnceLock<libloading::Library> = std::sync::OnceLock::new();
    if LIBRARY.get().is_none() {
        let executable = std::env::current_exe()?;
        let library = executable
            .parent()
            .ok_or_else(|| anyhow::anyhow!("앱 경로가 없습니다."))?
            .join("libMacPreviewSupport.dylib");
        // The app-bundled library has a fixed C entry point and lives until process exit.
        let loaded = unsafe { libloading::Library::new(library) }?;
        let _ = LIBRARY.set(loaded);
    }
    Ok(LIBRARY.get().unwrap())
}
pub fn preview(path: &Path) -> anyhow::Result<()> {
    let library = preview_library()?;
    let path = std::ffi::CString::new(path.to_string_lossy().as_bytes())?;
    unsafe {
        let function: libloading::Symbol<unsafe extern "C" fn(*const std::ffi::c_char) -> i32> =
            library.get(b"space_sniffer_preview\0")?;
        anyhow::ensure!(
            function(path.as_ptr()) == 1,
            "Quick Look 창을 표시하지 못했습니다."
        );
    }
    PREVIEW_VISIBLE.store(true, std::sync::atomic::Ordering::Relaxed);
    Ok(())
}
pub fn volume_note() -> &'static str {
    "APFS 공유·압축·스냅샷과 접근 권한 때문에 스캔 합계와 볼륨 사용량은 다를 수 있습니다."
}

pub fn preview_supported() -> bool {
    true
}

pub fn preview_message() -> Option<String> {
    None
}
#[cfg(feature = "qa")]
pub fn preview_observation() -> Option<super::PreviewObservation> {
    Some(super::PreviewObservation {
        visible: PREVIEW_VISIBLE.load(std::sync::atomic::Ordering::Relaxed),
        renderer: "Quick Look".into(),
        width: 0,
        height: 0,
    })
}

pub fn mounted_volumes_supported() -> bool {
    true
}

pub fn window_state(window: &mut gpui_kit::Window, state: &str) -> anyhow::Result<()> {
    let mode = match state {
        "normal" => 0,
        "minimized" => 1,
        "hidden" => 2,
        _ => anyhow::bail!("invalid_argument"),
    };
    let handle = raw_window_handle::HasWindowHandle::window_handle(window)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let raw_window_handle::RawWindowHandle::AppKit(handle) = handle.as_raw() else {
        anyhow::bail!("invalid_window")
    };
    let library = preview_library()?;
    unsafe {
        let function: libloading::Symbol<unsafe extern "C" fn(*mut std::ffi::c_void, i32) -> i32> =
            library.get(b"space_sniffer_window_state\0")?;
        anyhow::ensure!(
            function(handle.ns_view.as_ptr(), mode) == 1,
            "window_unavailable"
        );
    }
    Ok(())
}

pub fn resources() -> serde_json::Value {
    unsafe {
        let mut info: libc::proc_taskinfo = std::mem::zeroed();
        let size = std::mem::size_of_val(&info) as i32;
        let received = libc::proc_pidinfo(
            std::process::id() as i32,
            libc::PROC_PIDTASKINFO,
            0,
            (&mut info as *mut libc::proc_taskinfo).cast(),
            size,
        );
        let mut usage: libc::rusage = std::mem::zeroed();
        let usage_ok = libc::getrusage(libc::RUSAGE_SELF, &mut usage) == 0;
        if received == size && usage_ok {
            serde_json::json!({"pid":std::process::id(),"rss_bytes":info.pti_resident_size,"virtual_bytes":info.pti_virtual_size,"cpu_user_seconds":usage.ru_utime.tv_sec as f64+usage.ru_utime.tv_usec as f64/1e6,"cpu_system_seconds":usage.ru_stime.tv_sec as f64+usage.ru_stime.tv_usec as f64/1e6,"peak_rss_bytes":usage.ru_maxrss,"threads":info.pti_threadnum})
        } else {
            serde_json::json!({"pid":std::process::id(),"error":"proc_pidinfo_failed"})
        }
    }
}

pub fn window_observation(window: &gpui_kit::Window) -> serde_json::Value {
    let result = (|| -> anyhow::Result<i32> {
        let handle = raw_window_handle::HasWindowHandle::window_handle(window)
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        let raw_window_handle::RawWindowHandle::AppKit(handle) = handle.as_raw() else {
            anyhow::bail!("invalid_window")
        };
        unsafe {
            let function: libloading::Symbol<unsafe extern "C" fn(*mut std::ffi::c_void) -> i32> =
                preview_library()?.get(b"space_sniffer_window_observation\0")?;
            Ok(function(handle.ns_view.as_ptr()))
        }
    })();
    match result {
        Ok(bits) if bits >= 0 => {
            serde_json::json!({"window_visible":bits&1!=0,"window_minimized":bits&2!=0,"window_occluded":bits&4==0})
        }
        _ => {
            serde_json::json!({"window_visible":window.is_visible(),"window_minimized":null,"window_occluded":null})
        }
    }
}
pub fn volume_info(path: &std::path::Path) -> anyhow::Result<serde_json::Value> {
    let text = std::ffi::CString::new(path.as_os_str().as_encoded_bytes())?;
    let mut value: libc::statvfs = unsafe { std::mem::zeroed() };
    anyhow::ensure!(
        unsafe { libc::statvfs(text.as_ptr(), &mut value) } == 0,
        "volume_info_failed"
    );
    let total = (value.f_blocks as u64).saturating_mul(value.f_frsize as u64);
    let free = (value.f_bfree as u64).saturating_mul(value.f_frsize as u64);
    Ok(
        serde_json::json!({"path":path,"total_bytes":total,"free_bytes":free,"system_used_estimate_bytes":total.saturating_sub(free),"accounting_note":volume_note()}),
    )
}

pub fn titlebar_options() -> gpui_kit::TitlebarOptions {
    gpui_kit::TitlebarOptions {
        title: Some(env!("SPACER_PRODUCT_NAME").into()),
        appears_transparent: true,
        traffic_light_position: Some(gpui_kit::point(gpui_kit::px(10.), gpui_kit::px(16.))),
    }
}
pub fn header_inset() -> f32 {
    86.
}
pub fn window_created(_window: &gpui_kit::Window) {}
