use gpui_kit::*;
pub const BG: u32 = 0x0e1318;
pub const SURFACE: u32 = 0x161b20;
pub const BORDER: u32 = 0x29363d;
pub const TEXT: u32 = 0xdce3e7;
pub const MUTED: u32 = 0x91a0a8;
pub const ACCENT: u32 = 0x6ed4b3;
pub const SIDEBAR: f32 = 208.;
pub const DETAILS: f32 = 250.;
pub fn init(cx: &mut App) {
    let theme = gpui_kit::base::Theme::global_mut(cx);
    theme.appearance = gpui_kit::base::ThemeAppearance::Dark;
    theme.tokens.colors = gpui_kit::base::ColorTokens::dark();
}
