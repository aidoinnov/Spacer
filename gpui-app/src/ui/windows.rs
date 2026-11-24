//! One window composition path for user commands, startup, and automation.
use super::app::Explorer;
use gpui_kit::*;
use std::path::PathBuf;
thread_local! {static WINDOWS:std::cell::RefCell<Vec<WindowHandle<Explorer>>>=const {std::cell::RefCell::new(Vec::new())};}
pub fn register(handle: WindowHandle<Explorer>) {
    WINDOWS.with(|windows| windows.borrow_mut().push(handle));
}
pub fn handles(cx: &App) -> Vec<WindowHandle<Explorer>> {
    WINDOWS.with(|windows| {
        let mut windows = windows.borrow_mut();
        windows.retain(|w| w.read(cx).is_ok());
        windows.clone()
    })
}
pub struct OpenRequest {
    pub initial: Option<PathBuf>,
    pub qa_output: Option<PathBuf>,
    pub visible: bool,
    pub focus: bool,
}
impl Default for OpenRequest {
    fn default() -> Self {
        Self {
            initial: None,
            qa_output: None,
            visible: true,
            focus: true,
        }
    }
}
pub fn open(initial: Option<PathBuf>, cx: &mut App) -> anyhow::Result<WindowHandle<Explorer>> {
    open_request(
        OpenRequest {
            initial,
            ..Default::default()
        },
        cx,
    )
}
pub fn open_request(request: OpenRequest, cx: &mut App) -> anyhow::Result<WindowHandle<Explorer>> {
    let bounds = Bounds::centered(None, size(px(1340.), px(860.)), cx);
    let handle = cx.open_window(
        WindowOptions {
            show: request.visible,
            focus: request.focus,
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(crate::platform::titlebar_options()),
            window_min_size: Some(size(px(1040.), px(680.))),
            ..Default::default()
        },
        move |window, cx| {
            crate::platform::window_created(window);
            cx.new(|cx| Explorer::new(request.initial, request.qa_output, window, cx))
        },
    )?;
    register(handle);
    Ok(handle)
}
