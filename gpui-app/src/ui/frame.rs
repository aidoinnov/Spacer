//! Manual frames must discharge GPUI's temporary element-arena lease.
//! Normal platform frames already do this in GPUI's event loop.
use gpui_kit::{App, Window};

pub(super) fn draw(window: &mut Window, cx: &mut App) {
    window.draw(cx).clear(cx);
}
