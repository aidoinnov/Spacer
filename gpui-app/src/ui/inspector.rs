//! Selected-node metadata and volume summary; no navigation or platform APIs.
use super::{
    app::{Command, Explorer},
    icons::icon,
    theme::*,
};
use crate::model::bytes;
use gpui_kit::*;
impl Explorer {
    pub(super) fn inspector(&self, cx: &mut Context<Self>) -> AnyElement {
        let node = self
            .snapshot
            .as_ref()
            .and_then(|s| s.nodes.get(self.selected.unwrap_or(self.focus)));
        let mut content = div().p(px(22.)).flex().flex_col().gap_1().child(
            div()
                .text_size(px(10.))
                .text_color(rgb(MUTED))
                .mb_3()
                .child(if self.selected.is_some() {
                    "선택한 항목"
                } else {
                    "현재 위치"
                }),
        );
        if let Some(n) = node {
            content = content
                .child(
                    div()
                        .text_size(px(34.))
                        .text_color(rgb(ACCENT))
                        .mb_2()
                        .child(icon(if n.directory { "folder" } else { "file-text" }, 34.)),
                )
                .child(
                    div()
                        .text_size(px(17.))
                        .font_weight(FontWeight::MEDIUM)
                        .child(n.name.clone()),
                )
                .child(
                    div()
                        .text_size(px(10.))
                        .text_color(rgb(MUTED))
                        .mb(px(20.))
                        .child(n.path.clone()),
                )
                .child(detail_line("디스크 사용량", bytes(n.allocated)))
                .child(detail_line("파일 크기", bytes(n.logical)))
                .child(detail_line(
                    "수정일",
                    crate::model::timestamp(n.metadata.modified),
                ))
                .child(detail_line(
                    "생성일",
                    crate::model::timestamp(n.metadata.created),
                ))
                .child(detail_line(
                    "접근일",
                    crate::model::timestamp(n.metadata.accessed),
                ))
                .child(detail_line(
                    "유형",
                    if n.directory { "폴더" } else { "파일" }.into(),
                ))
                .child(detail_line(
                    "직접 하위 항목",
                    format!("{}개", n.children.len()),
                ));
        }
        if let Some(n) = node {
            let mut tags = div().flex().gap_3();
            for color in 1..=4 {
                let rgb_value = [0, 0xff4545, 0xffd61a, 0x34d65a, 0x007aff][color];
                let id = ["tag0", "tag1", "tag2", "tag3", "tag4"][color];
                tags = tags.child(
                    self.button(
                        id,
                        if crate::model::tag_color_index(self.tag_for(n.id)) == color as u8 {
                            "◉"
                        } else {
                            "●"
                        },
                        Command::Tag(color as u8),
                        true,
                        cx,
                    )
                    .text_color(rgb(rgb_value))
                    .px_0(),
                );
            }
            tags = tags.child(self.button("untag", "⊗", Command::Tag(0), true, cx));
            content = content
                .child(
                    div()
                        .mt_3()
                        .pt_5()
                        .border_t_1()
                        .border_color(rgb(BORDER))
                        .text_size(px(10.))
                        .text_color(rgb(MUTED))
                        .child("색상 태그"),
                )
                .child(tags)
                .child(div().mt_3().pt_5().border_t_1().border_color(rgb(BORDER)))
                .child(
                    self.button(
                        "reveal",
                        crate::platform::reveal_label(),
                        Command::Reveal,
                        !self.offline,
                        cx,
                    )
                    .text_size(px(11.)),
                )
                .child(
                    self.button("copy-path", "▤ 경로 복사", Command::CopyPath, true, cx)
                        .text_size(px(11.)),
                );
            if n.id != 0 {
                content = content.child(
                    self.button(
                        "trash",
                        "♲ 휴지통으로 이동…",
                        Command::Trash,
                        !self.offline && !self.scanning,
                        cx,
                    )
                    .text_size(px(11.))
                    .text_color(rgb(0xe46b6b)),
                );
            }
        }
        if let Some(snapshot) = &self.snapshot {
            content = content.child(detail_line(
                "분석 범위",
                match snapshot.volume_traversal.as_deref() {
                    Some("selectedVolume") => "선택한 볼륨".into(),
                    Some("allVolumes") => "다른 볼륨 포함".into(),
                    _ => "스냅샷에 범위 정보 없음".into(),
                },
            ));
        }
        if let Some(s) = &self.snapshot
            && s.volume_total > 0
        {
            content = content
                .child(
                    div()
                        .mt_5()
                        .pt_5()
                        .border_t_1()
                        .border_color(rgb(BORDER))
                        .text_size(px(10.))
                        .child("볼륨 전체"),
                )
                .child(
                    div()
                        .h(px(5.))
                        .w_full()
                        .my_2()
                        .rounded_full()
                        .bg(rgb(BORDER))
                        .child(div().h_full().rounded_full().bg(rgb(ACCENT)).w(relative(
                            s.volume_total.saturating_sub(s.volume_free) as f32
                                / s.volume_total as f32,
                        ))),
                )
                .child(detail_line("전체", bytes(s.volume_total)))
                .child(detail_line("여유 공간", bytes(s.volume_free)))
                .child(detail_line(
                    "시스템 사용량",
                    bytes(s.volume_total.saturating_sub(s.volume_free)),
                ))
                .child(
                    div()
                        .text_size(px(10.))
                        .text_color(rgb(MUTED))
                        .child(crate::platform::volume_note()),
                );
        }
        div()
            .id("inspector")
            .w(px(DETAILS))
            .h_full()
            .flex_shrink_0()
            .border_l_1()
            .border_color(rgb(BORDER))
            .bg(rgb(0x12181e))
            .overflow_y_scroll()
            .child(content)
            .into_any_element()
    }
}

fn detail_line(label: &str, value: String) -> impl IntoElement {
    div()
        .flex()
        .gap_2()
        .py_1()
        .text_size(px(10.))
        .child(
            div()
                .flex_1()
                .text_color(rgb(MUTED))
                .child(label.to_owned()),
        )
        .child(value)
}
