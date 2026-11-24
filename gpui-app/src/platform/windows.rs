#[path = "windows/preview.rs"]
mod preview;
use std::path::{Path, PathBuf};
pub fn focused_rescan_scope() -> &'static str {
    "root"
}
pub fn configure_child_process(command: &mut std::process::Command) {
    use std::os::windows::process::CommandExt;
    command.creation_flags(windows::Win32::System::Threading::CREATE_NO_WINDOW.0);
}
pub fn backend(directory: &Path) -> PathBuf {
    directory.join("ExplorerBackend.exe")
}
pub fn applications() -> std::path::PathBuf {
    std::env::var_os("ProgramFiles")
        .map(Into::into)
        .unwrap_or_else(|| "C:\\Program Files".into())
}
pub fn volumes() -> Vec<std::path::PathBuf> {
    ('A'..='Z')
        .map(|c| std::path::PathBuf::from(format!("{c}:\\")))
        .filter(|p| p.exists())
        .collect()
}

pub fn reveal_label() -> &'static str {
    "탐색기에서 보기"
}
pub fn scan_path(path: &std::path::Path) -> PathBuf {
    // A missing leaf still needs the existing parent's spelling (Temp/TEMP,
    // drive case and short names) before scope checks and error classification.
    let p = path
        .ancestors()
        .find_map(|ancestor| {
            std::fs::canonicalize(ancestor).ok().map(|parent| {
                let suffix = path.strip_prefix(ancestor).unwrap();
                if suffix.as_os_str().is_empty() {
                    parent
                } else {
                    parent.join(suffix)
                }
            })
        })
        .unwrap_or_else(|| path.to_path_buf());
    let text = p.to_string_lossy();
    if let Some(suffix) = text.strip_prefix("\\\\?\\UNC\\") {
        return format!("\\\\{suffix}").into();
    }
    if let Some(suffix) = text.strip_prefix("\\\\?\\") {
        return suffix.into();
    }
    p
}

pub fn preview(path: &Path) -> anyhow::Result<()> {
    preview::show(path)
}
pub fn volume_note() -> &'static str {
    "압축·희소 파일·하드 링크와 접근 권한 때문에 스캔 합계와 볼륨 사용량은 다를 수 있습니다."
}

pub fn preview_supported() -> bool {
    true
}
pub fn preview_message() -> Option<String> {
    preview::message()
}
#[cfg(feature = "qa")]
pub fn preview_observation() -> Option<super::PreviewObservation> {
    preview::observation().map(|p| super::PreviewObservation {
        visible: p.visible,
        renderer: p.renderer,
        width: p.width,
        height: p.height,
    })
}

pub fn mounted_volumes_supported() -> bool {
    true
}

pub fn window_state(window: &mut gpui_kit::Window, state: &str) -> anyhow::Result<()> {
    use windows::Win32::{
        Foundation::HWND,
        UI::WindowsAndMessaging::{SW_HIDE, SW_MINIMIZE, SW_RESTORE, ShowWindow},
    };
    let mode = match state {
        "normal" => SW_RESTORE,
        "minimized" => SW_MINIMIZE,
        "hidden" => SW_HIDE,
        _ => anyhow::bail!("invalid_argument"),
    };
    let handle = raw_window_handle::HasWindowHandle::window_handle(window)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let raw_window_handle::RawWindowHandle::Win32(handle) = handle.as_raw() else {
        anyhow::bail!("invalid_window")
    };
    unsafe {
        let _ = ShowWindow(HWND(handle.hwnd.get() as *mut _), mode);
    }
    Ok(())
}

pub fn resources() -> serde_json::Value {
    use windows::Win32::{
        Foundation::FILETIME,
        System::{
            ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS},
            Threading::{GetCurrentProcess, GetProcessTimes},
        },
    };
    unsafe {
        let process = GetCurrentProcess();
        let mut memory = PROCESS_MEMORY_COUNTERS {
            cb: std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32,
            ..Default::default()
        };
        let mut creation = FILETIME::default();
        let mut exit = FILETIME::default();
        let mut kernel = FILETIME::default();
        let mut user = FILETIME::default();
        if GetProcessMemoryInfo(
            process,
            &mut memory,
            std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32,
        )
        .is_err()
            || GetProcessTimes(process, &mut creation, &mut exit, &mut kernel, &mut user).is_err()
        {
            return serde_json::json!({"pid":std::process::id(),"error":"process_metrics_failed"});
        }
        let seconds =
            |t: FILETIME| (((t.dwHighDateTime as u64) << 32) | t.dwLowDateTime as u64) as f64 / 1e7;
        serde_json::json!({"pid":std::process::id(),"rss_bytes":memory.WorkingSetSize,"peak_rss_bytes":memory.PeakWorkingSetSize,"cpu_user_seconds":seconds(user),"cpu_system_seconds":seconds(kernel)})
    }
}

pub fn window_observation(window: &gpui_kit::Window) -> serde_json::Value {
    use windows::Win32::{
        Foundation::HWND,
        UI::WindowsAndMessaging::{IsIconic, IsWindowVisible},
    };
    if let Ok(handle) = raw_window_handle::HasWindowHandle::window_handle(window)
        && let raw_window_handle::RawWindowHandle::Win32(handle) = handle.as_raw()
    {
        let hwnd = HWND(handle.hwnd.get() as *mut _);
        return unsafe {
            serde_json::json!({"window_visible":IsWindowVisible(hwnd).as_bool(),"window_minimized":IsIconic(hwnd).as_bool(),"window_occluded":null})
        };
    }
    serde_json::json!({"window_visible":null,"window_minimized":null,"window_occluded":null})
}
pub fn volume_info(path: &std::path::Path) -> anyhow::Result<serde_json::Value> {
    use windows::{Win32::Storage::FileSystem::GetDiskFreeSpaceExW, core::PCWSTR};
    let wide: Vec<u16> = path
        .to_string_lossy()
        .encode_utf16()
        .chain(Some(0))
        .collect();
    let mut total = 0u64;
    let mut free = 0u64;
    unsafe {
        GetDiskFreeSpaceExW(
            PCWSTR(wide.as_ptr()),
            None,
            Some(&mut total),
            Some(&mut free),
        )?;
    }
    Ok(
        serde_json::json!({"path":path,"total_bytes":total,"free_bytes":free,"system_used_estimate_bytes":total.saturating_sub(free),"accounting_note":volume_note()}),
    )
}

pub fn titlebar_options() -> gpui_kit::TitlebarOptions {
    gpui_kit::TitlebarOptions {
        title: Some("Space Sniffer — GPUI".into()),
        ..Default::default()
    }
}
pub fn header_inset() -> f32 {
    18.
}
pub fn window_created(window: &gpui_kit::Window) {
    use windows::Win32::{
        Foundation::HWND,
        Graphics::Dwm::{DWMWA_USE_IMMERSIVE_DARK_MODE, DwmSetWindowAttribute},
    };
    if let Ok(handle) = raw_window_handle::HasWindowHandle::window_handle(window)
        && let raw_window_handle::RawWindowHandle::Win32(handle) = handle.as_raw()
    {
        let enabled = 1i32;
        unsafe {
            let _ = DwmSetWindowAttribute(
                HWND(handle.hwnd.get() as *mut _),
                DWMWA_USE_IMMERSIVE_DARK_MODE,
                (&enabled as *const i32).cast(),
                std::mem::size_of_val(&enabled) as u32,
            );
        }
    }
}

#[cfg(test)]
mod scan_path_tests {
    use super::*;
    #[test]
    fn missing_leaf_retains_existing_parent_spelling() {
        let directory = tempfile::tempdir().unwrap();
        assert!(
            !scan_path(directory.path())
                .to_string_lossy()
                .ends_with('\\')
        );
        let alias = PathBuf::from(directory.path().to_string_lossy().to_uppercase());
        let missing = alias.join("not-created").join("leaf");
        assert_eq!(
            scan_path(&missing),
            scan_path(directory.path()).join("not-created").join("leaf")
        );
    }
}
