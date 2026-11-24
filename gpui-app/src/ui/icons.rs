use gpui_kit::*;
pub fn icon(name: &str, size: f32) -> Svg {
    svg()
        .path(format!("icons/{name}.svg"))
        .size(px(size))
        .text_color(rgb(super::theme::TEXT))
        .flex_shrink_0()
}
