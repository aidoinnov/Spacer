use super::{
    app::{Command, Explorer},
    theme::*,
};
use gpui_kit::{base::Popup, *};
impl Explorer {
    pub(super) fn popup(
        &self,
        id: &'static str,
        label: &str,
        command: Command,
        open: bool,
        kind: usize,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let mut popup = Popup::new(id, self.button(id, label.to_owned(), command, true, cx));
        if open {
            let mut menu = div()
                .id(("menu", kind))
                .w(px(if kind == 0 { 350. } else { 240. }))
                .p_3()
                .flex()
                .flex_col()
                .gap_1()
                .bg(rgb(0x242a30))
                .rounded_md()
                .border_1()
                .border_color(rgb(BORDER))
                .shadow_lg()
                .text_size(px(11.))
                .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                    this.settings = false;
                    this.more_menu = false;
                    this.filter_help = false;
                    cx.notify();
                }));
            if kind == 0 {
                menu=menu.child(div().text_size(px(14.)).mb_2().child("빠른 필터")).child("*.zip;*.dmg    파일명 OR\n*.zip;>100mb    크기 조건 결합\n|*.tmp         제외\n>30d           수정 후 30일 초과\n:tag:red       빨강 태그\n\\node_modules 경로의 폴더 이름\n:class:Video/Movies 동영상 클래스\nlogicalsize>1gb 논리 크기 기준").child(div().mt_2().text_size(px(10.)).text_color(rgb(MUTED)).child("크기 단위는 1 KB = 1,024 B입니다.\n입력 후 Return 또는 적용을 누르세요."));
            } else {
                if kind == 2 {
                    menu = menu
                        .child(self.button(
                            "menu-new-window",
                            "새 창",
                            Command::NewWindow,
                            true,
                            cx,
                        ))
                        .child(self.button(
                            "menu-open",
                            "스냅샷 열기…",
                            Command::Load,
                            !self.scanning,
                            cx,
                        ))
                        .child(self.button(
                            "menu-save",
                            "스냅샷 저장…",
                            Command::Save,
                            self.snapshot.is_some(),
                            cx,
                        ))
                        .child(self.button(
                            "menu-export",
                            "파일 목록 내보내기…",
                            Command::Export,
                            self.snapshot.is_some(),
                            cx,
                        ))
                        .child(self.button(
                            "menu-configured-export",
                            "설정·템플릿으로 내보내기…",
                            Command::ConfiguredExport,
                            self.snapshot.as_ref().is_some_and(|s| s.document.is_some()),
                            cx,
                        ))
                        .child(div().h(px(1.)).my_2().bg(rgb(BORDER)));
                } else {
                    menu = menu.child("표시 깊이");
                    let mut depth = div().flex().gap_1();
                    for i in 1..=6 {
                        let ids = ["d0", "d1", "d2", "d3", "d4", "d5", "d6"];
                        depth = depth.child(
                            self.button(ids[i], i.to_string(), Command::SetDepth(i), true, cx)
                                .text_color(rgb(if self.depth == i { ACCENT } else { TEXT })),
                        );
                    }
                    menu = menu.child(depth).child(self.button(
                        "menu-mode",
                        if self.mode == crate::projection::SizeMode::Allocated {
                            "크기 기준: 디스크 사용량"
                        } else {
                            "크기 기준: 파일 크기"
                        },
                        Command::Logical,
                        true,
                        cx,
                    ));
                }
                menu = menu
                    .child(self.button(
                        "menu-hidden",
                        if self.hidden {
                            "✓ 숨김 파일 표시"
                        } else {
                            "   숨김 파일 표시"
                        },
                        Command::Hidden,
                        true,
                        cx,
                    ))
                    .child(self.button(
                        "menu-color",
                        if self.color_by_type {
                            "✓ 파일 유형별 색상"
                        } else {
                            "   파일 유형별 색상"
                        },
                        Command::Color,
                        true,
                        cx,
                    ));
                if kind == 2 {
                    menu = menu.child(self.button(
                        "menu-mounted-volumes",
                        if self.include_mounted {
                            "✓ 다른 볼륨 포함 · 다시 분석"
                        } else {
                            "다른 볼륨 포함 · 다시 분석"
                        },
                        Command::MountedVolumes,
                        !self.offline && crate::platform::mounted_volumes_supported(),
                        cx,
                    ));
                    menu = menu.child(self.button(
                        "menu-rescan-focus",
                        "현재 폴더 다시 스캔",
                        Command::RescanFocus,
                        !self.offline && !self.scanning,
                        cx,
                    ));
                    menu = menu.child(self.button(
                        "menu-watch",
                        if self.watching {
                            "✓ 파일 변경 시 자동 재스캔"
                        } else {
                            "   파일 변경 시 자동 재스캔"
                        },
                        Command::Watch,
                        !self.offline,
                        cx,
                    ));
                }
            }
            popup = popup.content(menu);
        }
        popup.into_any_element()
    }
}
