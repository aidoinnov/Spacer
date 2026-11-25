pub(crate) mod paths;
pub(crate) mod process;
use std::path::PathBuf;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "macos")]
use macos as host;
#[cfg(target_os = "windows")]
use windows as host;
pub fn focused_rescan_scope() -> &'static str {
    host::focused_rescan_scope()
}
/// The single OS composition boundary. UI/model/layout contain no OS cfgs.
pub fn backend() -> PathBuf {
    process::backend()
}

pub fn engine_watches() -> bool {
    #[cfg(target_os = "macos")]
    {
        true
    }
    #[cfg(not(target_os = "macos"))]
    {
        false
    }
}

pub fn applications() -> std::path::PathBuf {
    host::applications()
}
pub fn volumes() -> Vec<std::path::PathBuf> {
    host::volumes()
}

pub fn reveal_label() -> &'static str {
    host::reveal_label()
}
pub fn scan_path(path: &std::path::Path) -> PathBuf {
    paths::scan_path(path)
}

pub fn preview(path: &std::path::Path) -> anyhow::Result<()> {
    host::preview(path)
}
pub fn volume_note() -> &'static str {
    host::volume_note()
}

pub fn preview_supported() -> bool {
    host::preview_supported()
}

pub fn preview_message() -> Option<String> {
    host::preview_message()
}
#[cfg(feature = "qa")]
#[derive(Clone, Debug, serde::Serialize)]
pub struct PreviewObservation {
    pub visible: bool,
    pub renderer: String,
    pub width: u32,
    pub height: u32,
}
#[cfg(feature = "qa")]
pub fn preview_observation() -> Option<PreviewObservation> {
    host::preview_observation()
}

pub fn mounted_volumes_supported() -> bool {
    host::mounted_volumes_supported()
}

pub mod control;

pub fn window_state(window: &mut gpui_kit::Window, state: &str) -> anyhow::Result<()> {
    host::window_state(window, state)
}

pub fn resources() -> serde_json::Value {
    host::resources()
}

pub fn window_observation(window: &gpui_kit::Window) -> serde_json::Value {
    host::window_observation(window)
}
pub fn volume_info(path: &std::path::Path) -> anyhow::Result<serde_json::Value> {
    host::volume_info(path)
}

pub fn titlebar_options() -> gpui_kit::TitlebarOptions {
    host::titlebar_options()
}
pub fn header_inset() -> f32 {
    host::header_inset()
}
pub fn window_created(window: &gpui_kit::Window) {
    host::window_created(window)
}
