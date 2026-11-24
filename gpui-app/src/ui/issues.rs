use super::{
    app::{Command, Explorer},
    theme::*,
};
use gpui_kit::*;
impl Explorer {
    pub(super) fn issues_sheet(&self, cx: &mut Context<Self>) -> Option<AnyElement> {
        if !self.show_issues {
            return None;
        }
        let snapshot = self.snapshot.as_ref();
        let lines = snapshot.map(|s| s.issues.join("\n\n")).unwrap_or_default();
        let count = snapshot.map_or(0, |s| s.errors);
        Some(
            div()
                .absolute()
                .inset_0()
                .flex()
                .items_center()
                .justify_center()
                .bg(rgba(0x00000099))
                .occlude()
                .child(
                    div()
                        .w(px(720.))
                        .h(px(480.))
                        .p_5()
                        .rounded_lg()
                        .bg(rgb(SURFACE))
                        .flex()
                        .flex_col()
                        .gap_3()
                        .child(div().text_lg().child("스캔 중 읽지 못한 경로"))
                        .child(div().text_xs().text_color(rgb(MUTED)).child(format!(
                            "접근 오류 {count}개 · 오류 기록은 최대 500개까지 표시합니다."
                        )))
                        .child(
                            div()
                                .id("issue-records")
                                .flex_1()
                                .min_h_0()
                                .overflow_y_scroll()
                                .text_xs()
                                .child(if lines.is_empty() {
                                    "저장된 오류 기록이 없습니다.".to_string()
                                } else {
                                    lines
                                }),
                        )
                        .child(self.button("close-issues", "닫기", Command::Issues, true, cx)),
                )
                .into_any_element(),
        )
    }
}
