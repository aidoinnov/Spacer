use super::{
    app::{Command, Explorer},
    theme,
};
use crate::{layout::Rect, model::bytes};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
impl Explorer {
    pub fn mosaic(&self, cx: &mut Context<Self>) -> AnyElement {
        let geometry = self.geometry.clone();
        let source = self.projection.clone();
        let progress = self.progress.clone().filter(|_| self.uses_progress_map());
        let mode = self.mode;
        let focus = self.focus;
        let depth = self.depth;
        let selected = self.selected;
        let hovered = self.hovered;
        let hit = self.tiles.clone();
        let presentation = self.presentation.clone();
        let by_type = self.color_by_type;
        let tags = self.tags.clone();
        let a11y_actions: super::map_accessibility::Actions = Default::default();
        let published_actions = a11y_actions.clone();
        let a11y_tiles = hit.clone();
        let a11y_source = self.snapshot.clone();
        let view = cx.weak_entity();
        let scale = std::rc::Rc::new(std::cell::Cell::new(1f32));
        let a11y_scale = scale.clone();
        let tooltip = self
            .hovered
            .and_then(|id| self.snapshot.as_ref().and_then(|s| s.nodes.get(id)))
            .map(|node| {
                format!(
                    "{}\n디스크: {} · 파일: {}\n수정: {}",
                    node.path,
                    bytes(node.allocated),
                    bytes(node.logical),
                    crate::model::timestamp(node.metadata.modified)
                )
            });
        div()
            .id("treemap")
            .role(Role::Group)
            .aria_label("디스크 트리맵")
            .a11y_synthetic_children(move |builder| {
                if let Some(source) = &a11y_source {
                    super::map_accessibility::publish(
                        builder,
                        &a11y_tiles.borrow(),
                        source,
                        focus,
                        a11y_scale.get(),
                        &published_actions,
                    );
                }
            })
            .when_some(tooltip, |map, text| {
                map.tooltip(move |_, cx| {
                    cx.new(|_| super::map_accessibility::MapTip(text.clone()))
                        .into()
                })
            })
            .flex_1()
            .size_full()
            .min_h_0()
            .overflow_hidden()
            .on_mouse_move(cx.listener(|this, event: &MouseMoveEvent, _, cx| {
                let x: f32 = event.position.x.into();
                let y: f32 = event.position.y.into();
                let hovered = this
                    .tiles
                    .borrow()
                    .iter()
                    .rev()
                    .find(|t| {
                        t.interactive
                            && t.opacity > 0.5
                            && x >= t.rect.x
                            && y >= t.rect.y
                            && x < t.rect.x + t.rect.w
                            && y < t.rect.y + t.rect.h
                    })
                    .and_then(|t| {
                        t.id.filter(|&id| {
                            this.snapshot
                                .as_ref()
                                .and_then(|s| s.nodes.get(id))
                                .is_some_and(|n| n.path == t.path)
                        })
                    });
                if this.hovered != hovered {
                    this.hovered = hovered;
                    cx.notify();
                }
            }))
            .on_hover(cx.listener(|this, hovered, _, cx| {
                if !hovered && this.hovered.take().is_some() {
                    cx.notify();
                }
            }))
            .on_click(cx.listener(|this, event: &ClickEvent, window, cx| {
                window.focus(&this.focus_handle, cx);
                // A single folder click changes the view; the second native click
                // must not activate a child newly painted at the same position.
                if event.click_count() > 1 {
                    if let Some((id, path)) = this.click_anchor.take()
                        && let Some(parent) = this
                            .snapshot
                            .as_ref()
                            .and_then(|s| s.nodes.get(id))
                            .filter(|n| n.path == path)
                            .and_then(|n| n.parent)
                    {
                        this.command(Command::Navigate(parent), window, cx);
                    }
                    return;
                }
                this.click_anchor = None;
                let point = event.position();
                let x: f32 = point.x.into();
                let y: f32 = point.y.into();
                let target = this
                    .tiles
                    .borrow()
                    .iter()
                    .rev()
                    .find(|t| {
                        t.interactive
                            && t.opacity > 0.5
                            && x >= t.rect.x
                            && y >= t.rect.y
                            && x < t.rect.x + t.rect.w
                            && y < t.rect.y + t.rect.h
                    })
                    .cloned();
                if let Some(t) = target {
                    if t.folder {
                        this.click_anchor = None;
                        this.command(Command::NavigatePath(t.path.into()), window, cx)
                    } else if let Some(id) = t.id
                        && this
                            .snapshot
                            .as_ref()
                            .and_then(|s| s.nodes.get(id))
                            .is_some_and(|n| n.path == t.path)
                    {
                        this.click_anchor = Some((id, t.path));
                        this.command(Command::Select(id), window, cx)
                    }
                }
            }))
            .on_mouse_down(
                MouseButton::Right,
                cx.listener(|this, event: &MouseDownEvent, _, cx| {
                    if this.scanning {
                        return;
                    }
                    let x: f32 = event.position.x.into();
                    let y: f32 = event.position.y.into();
                    let id = this
                        .tiles
                        .borrow()
                        .iter()
                        .rev()
                        .find(|t| {
                            t.interactive
                                && t.opacity > 0.5
                                && x >= t.rect.x
                                && x < t.rect.x + t.rect.w
                                && y >= t.rect.y
                                && y < t.rect.y + t.rect.h
                        })
                        .and_then(|t| t.id);
                    if let Some(id) = id {
                        this.selected = Some(id);
                        this.context_menu = Some(event.position);
                        cx.notify();
                    }
                }),
            )
            .child(
                canvas(
                    move |bounds, window, cx| {
                        scale.set(window.scale_factor());
                        let area = Rect {
                            x: bounds.origin.x.into(),
                            y: bounds.origin.y.into(),
                            w: bounds.size.width.into(),
                            h: bounds.size.height.into(),
                        };
                        let next = if let Some(progress) = &progress {
                            geometry.borrow_mut().suspend();
                            crate::layout::overview_tiles(progress, mode, area)
                        } else {
                            source
                                .as_ref()
                                .map(|p| geometry.borrow_mut().get(p, focus, depth, selected, area))
                                .unwrap_or_default()
                        };
                        if geometry.borrow().pending() {
                            window.request_animation_frame();
                        }
                        let (frame, active) = presentation.borrow_mut().frame(
                            next,
                            std::time::Instant::now(),
                            cx.reduce_motion(),
                        );
                        if active {
                            window.request_animation_frame();
                        }
                        *hit.borrow_mut() = frame.clone();
                        frame
                    },
                    move |_, tiles, window, cx| {
                        super::map_accessibility::install(&a11y_actions, &view, window);
                        let boxes: std::collections::HashMap<_, _> =
                            tiles.iter().map(|t| (t.path.clone(), t.rect)).collect();
                        for tile in tiles {
                            let r = tile.rect;
                            if r.w < 1. || r.h < 1. {
                                continue;
                            }
                            let bounds =
                                Bounds::new(point(px(r.x), px(r.y)), size(px(r.w), px(r.h)));
                            let mut base = category_color(&tile.name, tile.folder, by_type);
                            if let Some(color) = tags.get(&tile.path).copied() {
                                base = match crate::model::tag_color_index(color) {
                                    1 => [1., 0.27, 0.27],
                                    2 => [1., 0.84, 0.1],
                                    3 => [0.2, 0.84, 0.35],
                                    4 => [0., 0.48, 1.],
                                    _ => base,
                                };
                            }
                            let factor = if tile.folder {
                                (0.29 - tile.level as f32 * 0.025).max(0.16)
                            } else {
                                0.46
                            };
                            let bg = [0.07, 0.09, 0.115];
                            let fill = Rgba {
                                r: base[0] * factor + bg[0] * (1. - factor),
                                g: base[1] * factor + bg[1] * (1. - factor),
                                b: base[2] * factor + bg[2] * (1. - factor),
                                a: tile.opacity,
                            };
                            let stroke = Rgba {
                                r: base[0],
                                g: base[1],
                                b: base[2],
                                a: tile.opacity * if tile.folder { 0.45 } else { 0.70 },
                            };
                            let paint = |window: &mut Window, cx: &mut App| {
                                window.paint_quad(quad(
                                    bounds,
                                    Corners::all(px(4.)),
                                    fill,
                                    px(1.),
                                    stroke,
                                    BorderStyle::Solid,
                                ));
                                if (selected.is_some() && selected == tile.id
                                    || hovered.is_some() && hovered == tile.id)
                                    && tile.interactive
                                {
                                    window.paint_quad(quad(
                                        bounds,
                                        Corners::all(px(4.)),
                                        rgba(0),
                                        px(2.),
                                        rgb(theme::TEXT),
                                        BorderStyle::Solid,
                                    ));
                                }
                                if r.w > 34. && r.h > 22. {
                                    let title = format!(
                                        "{}{}",
                                        if tile.folder && tile.interactive {
                                            "▸ "
                                        } else {
                                            ""
                                        },
                                        tile.name
                                    );
                                    let title_bounds = if tile.expanded {
                                        Bounds::new(
                                            bounds.origin,
                                            size(px((r.w - 90.).max(0.)), bounds.size.height),
                                        )
                                    } else {
                                        bounds
                                    };
                                    paint_text(
                                        title,
                                        point(px(r.x + 8.), px(r.y + 6.)),
                                        title_bounds,
                                        tile.opacity,
                                        window,
                                        cx,
                                    );
                                    if tile.expanded {
                                        paint_text(
                                            bytes(tile.weight),
                                            point(px(r.x + r.w - 85.), px(r.y + 6.)),
                                            bounds,
                                            tile.opacity,
                                            window,
                                            cx,
                                        );
                                    } else if r.h > 49. {
                                        paint_text(
                                            bytes(tile.weight),
                                            point(px(r.x + 8.), px(r.y + 26.)),
                                            bounds,
                                            tile.opacity,
                                            window,
                                            cx,
                                        );
                                    }
                                }
                            };
                            if let Some(parent) =
                                tile.parent_path.as_ref().and_then(|p| boxes.get(p))
                            {
                                let clip = Bounds::new(
                                    point(px(parent.x + 3.), px(parent.y + 25.)),
                                    size(px((parent.w - 6.).max(0.)), px((parent.h - 28.).max(0.))),
                                );
                                window.with_content_mask(
                                    Some(ContentMask { bounds: clip }),
                                    |window| paint(window, cx),
                                );
                            } else {
                                paint(window, cx);
                            }
                        }
                    },
                )
                .size_full(),
            )
            .into_any_element()
    }
}
pub fn category_color(name: &str, folder: bool, by_type: bool) -> [f32; 3] {
    if folder || !by_type {
        return [0.22, 0.47, 0.53];
    }
    match name
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_lowercase()
        .as_str()
    {
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "heic" | "svg" => [0.55, 0.45, 0.77],
        "mp4" | "mov" | "mkv" | "avi" => [0.30, 0.57, 0.85],
        "mp3" | "wav" | "flac" | "aac" => [0.76, 0.46, 0.66],
        "zip" | "gz" | "tar" | "dmg" | "7z" | "rar" => [0.79, 0.57, 0.30],
        "rs" | "swift" | "js" | "ts" | "py" | "c" | "h" | "cpp" | "json" => [0.36, 0.64, 0.52],
        "txt" | "md" | "pdf" | "doc" | "docx" => [0.63, 0.65, 0.41],
        _ => [0.41, 0.49, 0.59],
    }
}
fn paint_text(
    text: String,
    origin: Point<Pixels>,
    bounds: Bounds<Pixels>,
    opacity: f32,
    window: &mut Window,
    cx: &mut App,
) {
    let mut color = rgb(theme::TEXT);
    color.a = opacity;
    let run = TextRun {
        len: text.len(),
        font: Font {
            family: "Noto Sans KR".into(),
            ..Font::default()
        },
        color: color.into(),
        ..TextRun::default()
    };
    let line = window
        .text_system()
        .shape_line(text.into(), px(11.), &[run], None);
    window.with_content_mask(Some(ContentMask { bounds }), |window| {
        let _ = line.paint(origin, px(18.), TextAlign::Left, None, window, cx);
    });
}
