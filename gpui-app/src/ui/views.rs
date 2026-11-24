use super::icons::icon;
use super::{
    app::{Command, Explorer},
    theme::*,
};
use crate::{model::bytes, projection::SizeMode};
use gpui_kit::base::{
    Button,
    input::{Input, InputBase},
};
use gpui_kit::*;
impl Explorer {
    pub(super) fn button(
        &self,
        id: &'static str,
        label: impl Into<SharedString>,
        action: Command,
        enabled: bool,
        cx: &mut Context<Self>,
    ) -> Button {
        let label = label.into();
        let glyph = match id {
            "choose" => Some(("folder-plus", "폴더 스캔")),
            "welcome-choose" => Some(("folder-plus", "폴더를 선택해서 시작")),
            "back" => Some(("chevron-left", "")),
            "forward" => Some(("chevron-right", "")),
            "up" => Some(("arrow-up", "상위 폴더")),
            "refresh" => Some((if self.scanning { "square" } else { "rotate-cw" }, "")),
            "more" => Some(("circle-ellipsis", "")),
            "settings" => Some(("sliders-horizontal", "")),
            "help" => Some(("circle-question-mark", "")),
            "list" => Some((if self.list_mode { "grid-2x2" } else { "list" }, "")),
            "copy-path" => Some(("copy", "경로 복사")),
            "reveal" => Some(("external-link", crate::platform::reveal_label())),
            "trash" => Some(("trash", "휴지통으로 이동…")),
            _ => None,
        };
        let content = if let Some((name, text)) = glyph {
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(icon(name, 12.))
                .child(text)
                .into_any_element()
        } else {
            div().child(label.clone()).into_any_element()
        };
        Button::new(id)
            .accessibility_label(label.clone())
            .child(content)
            .px_2()
            .py_1()
            .rounded_md()
            .text_color(rgb(TEXT))
            .disabled(!enabled)
            .on_click(
                cx.listener(move |this, _, window, cx| this.command(action.clone(), window, cx)),
            )
    }
    pub fn row(&self, index: usize, cx: &mut Context<Self>) -> AnyElement {
        let Some(p) = &self.projection else {
            return div().into_any_element();
        };
        let Some(&id) = p.children.get(index) else {
            return div().into_any_element();
        };
        let n = &p.source.nodes[id];
        let name = n.name.clone();
        div()
            .id(("node", id))
            .role(Role::Button)
            .aria_label(format!("{}, {}", n.name, bytes(p.weights[id])))
            .flex()
            .items_center()
            .h(px(54.))
            .px_3()
            .mx_5()
            .mb_1()
            .rounded_md()
            .gap_3()
            .bg(rgb(if self.selected == Some(id) {
                0x1c302c
            } else {
                0x13181d
            }))
            .cursor_pointer()
            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                this.command(Command::Select(id), window, cx);
                if event.click_count() >= 2 {
                    this.command(Command::Navigate(id), window, cx)
                }
            }))
            .child(icon(if n.directory { "folder" } else { "file" }, 16.))
            .child(div().flex_1().overflow_hidden().child(name))
            .child(
                div()
                    .text_xs()
                    .text_color(rgb(MUTED))
                    .child(bytes(p.weights[id])),
            )
            .child("›")
            .into_any_element()
    }
    fn sidebar(&self, cx: &mut Context<Self>) -> AnyElement {
        let home = std::env::home_dir().unwrap_or_default();
        let locations = [
            ("홈 폴더", "house", home.clone()),
            ("다운로드", "circle-arrow-down", home.join("Downloads")),
            ("데스크탑", "monitor", home.join("Desktop")),
            (
                "응용 프로그램",
                "app-window",
                crate::platform::applications(),
            ),
        ];
        let mut side = div()
            .w(px(SIDEBAR))
            .h_full()
            .flex_shrink_0()
            .flex()
            .flex_col()
            .bg(rgb(0x13191f))
            .border_r_1()
            .border_color(rgb(BORDER))
            .child(
                div()
                    .px(px(22.))
                    .pt_6()
                    .pb_2()
                    .text_size(px(10.))
                    .text_color(rgb(MUTED))
                    .child("즐겨찾기"),
            );
        for (index, (label, icon, path)) in locations.into_iter().enumerate() {
            let active = self
                .snapshot
                .as_ref()
                .is_some_and(|s| std::path::Path::new(&s.root) == path);
            side = side.child(
                div()
                    .id(("location", index))
                    .mx_2()
                    .px_3()
                    .h_9()
                    .rounded_md()
                    .flex()
                    .items_center()
                    .gap_2()
                    .text_size(px(12.))
                    .bg(rgb(if active { 0x1b2a29 } else { 0x13191f }))
                    .cursor_pointer()
                    .child(super::icons::icon(icon, 16.))
                    .child(label)
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.open_location(path.clone(), window, cx)
                    })),
            );
        }
        side = side.child(
            div()
                .px(px(22.))
                .pt(px(29.))
                .pb_2()
                .text_size(px(10.))
                .text_color(rgb(MUTED))
                .child("볼륨"),
        );
        for (index, path) in self.volumes.iter().cloned().enumerate() {
            let label = path
                .file_name()
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_else(|| path.display().to_string());
            side = side.child(
                div()
                    .id(("volume", index))
                    .mx_2()
                    .px_3()
                    .h_9()
                    .flex()
                    .items_center()
                    .gap_2()
                    .text_size(px(12.))
                    .cursor_pointer()
                    .child(icon("hard-drive", 16.))
                    .child(label)
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.open_location(path.clone(), window, cx)
                    })),
            );
        }
        side.child(div().flex_1()).child(div().m(px(14.)).p_4().rounded_md().bg(rgb(0x1b2026)).flex().flex_col().gap_3().child(div().text_size(px(12.)).child("▦  사용량을 한눈에")).child(div().text_size(px(11.)).text_color(rgb(MUTED)).child("큰 영역부터 살펴보세요.\n폴더를 더블 클릭하면\n안쪽을 자세히 볼 수 있어요.")).child(self.button("load-side","스냅샷 열기…",Command::Load,!self.scanning,cx).text_color(rgb(ACCENT)))).into_any_element()
    }
    fn welcome(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .flex_1()
            .h_full()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            .gap_3()
            .child(
                div()
                    .size(px(112.))
                    .rounded_3xl()
                    .bg(rgb(0x142020))
                    .text_color(rgb(ACCENT))
                    .text_size(px(48.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .mb_4()
                    .child(icon("grid-2x2", 18.).text_color(rgb(ACCENT))),
            )
            .child(
                div()
                    .text_size(px(27.))
                    .child("디스크 공간, 어디에 쓰이고 있나요?"),
            )
            .child(
                div()
                    .text_size(px(13.))
                    .text_color(rgb(MUTED))
                    .child("폴더를 스캔하면 파일과 폴더의 크기를 지도로 보여드립니다."),
            )
            .child(
                self.button(
                    "welcome-choose",
                    "폴더를 선택해서 시작",
                    Command::Browse,
                    true,
                    cx,
                )
                .mt_4()
                .bg(rgb(ACCENT))
                .text_color(rgb(BG))
                .px_5()
                .py_2(),
            )
            .child(
                div()
                    .text_size(px(11.))
                    .text_color(rgb(MUTED))
                    .child("또는 이 창에 폴더를 드래그하세요"),
            )
            .child(
                div()
                    .mt(px(65.))
                    .flex()
                    .gap_8()
                    .text_size(px(10.))
                    .text_color(rgb(MUTED))
                    .child("▦  크기에 비례하는 트리맵")
                    .child("≡  이름·크기·기간 필터")
                    .child("◇  태그와 보고서"),
            )
            .into_any_element()
    }
    fn workspace(&self, cx: &mut Context<Self>) -> AnyElement {
        let title = self
            .snapshot
            .as_ref()
            .map(|s| s.nodes[self.focus].name.clone())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| {
                self.root
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_else(|| self.root.display().to_string())
            });
        let total = if let Some(p) = self.progress.as_ref().filter(|_| self.uses_progress_map()) {
            if self.mode == SizeMode::Logical {
                p.logical
            } else {
                p.allocated
            }
        } else {
            self.projection
                .as_ref()
                .map_or(0, |p| p.weights[self.focus])
        };
        let mut nav = div()
            .h(px(47.))
            .flex_shrink_0()
            .px(px(18.))
            .flex()
            .gap_1()
            .items_center()
            .text_size(px(11.))
            .child(self.button("back", "‹", Command::Back, !self.history.is_empty(), cx))
            .child(self.button(
                "forward",
                "›",
                Command::Forward,
                !self.future.is_empty(),
                cx,
            ))
            .child(self.button("up", "↑ 상위 폴더", Command::Up, self.can_up(), cx));
        let mut crumbs = div().flex_1().flex().items_center().overflow_hidden();
        for (index, path) in self.breadcrumb_paths().into_iter().enumerate() {
            let label = crate::navigation::label(&path);
            crumbs = crumbs
                .child(
                    div()
                        .id(("crumb", index))
                        .px_1()
                        .cursor_pointer()
                        .child(label)
                        .on_click(cx.listener(move |this, _, window, cx| {
                            this.command(Command::NavigatePath(path.clone()), window, cx)
                        })),
                )
                .child("›");
        }
        nav = nav.child(crumbs);
        nav = nav.child(self.button(
            "refresh",
            if self.scanning { "■" } else { "⟳" },
            if self.scanning {
                Command::Cancel
            } else {
                Command::Rescan
            },
            !self.offline,
            cx,
        ));
        let header = div()
            .flex()
            .items_end()
            .px_6()
            .pt(px(13.))
            .pb_5()
            .gap_3()
            .child(
                div()
                    .text_size(px(25.))
                    .font_weight(FontWeight::MEDIUM)
                    .flex_1()
                    .overflow_hidden()
                    .child(title),
            )
            .child(div().text_size(px(26.)).child(bytes(total)))
            .child(
                div()
                    .pb_1()
                    .text_size(px(10.))
                    .text_color(rgb(MUTED))
                    .child(if self.mode == SizeMode::Allocated {
                        "디스크 사용량"
                    } else {
                        "파일 크기"
                    }),
            );
        let filter = div()
            .mx_5()
            .mb(px(10.))
            .px(px(13.))
            .h(px(38.))
            .flex_shrink_0()
            .flex()
            .items_center()
            .gap_2()
            .bg(rgb(0x191e23))
            .rounded_md()
            .text_size(px(11.))
            .child(div().text_color(rgb(ACCENT)).child("≡"))
            .child(
                div().flex_1().h(px(27.)).child(
                    InputBase::new("filter-field")
                        .h_full()
                        .child(Input::new(&self.filter_input)),
                ),
            )
            .child(
                self.button(
                    "filter",
                    "적용",
                    Command::Filter,
                    self.snapshot.is_some(),
                    cx,
                )
                .text_size(px(9.))
                .bg(rgb(0x30363a)),
            )
            .child(self.popup("help", "ⓘ", Command::Help, self.filter_help, 0, cx))
            .child(self.popup("settings", "☷", Command::Settings, self.settings, 1, cx))
            .child(self.button(
                "list",
                if self.list_mode { "▦" } else { "☰" },
                Command::List,
                true,
                cx,
            ));
        let mut center = div()
            .flex_1()
            .h_full()
            .min_w_0()
            .flex()
            .flex_col()
            .child(nav)
            .child(header)
            .child(filter);
        if self.scanning {
            let mut progress = div()
                .mx_5()
                .mb_2()
                .flex()
                .flex_col()
                .gap_1()
                .text_size(px(10.))
                .text_color(rgb(ACCENT))
                .child("스캔 진행 중 · 표시 용량은 현재까지 집계한 값입니다");
            if let Some(p) = &self.progress {
                progress = progress
                    .child(format!(
                        "폴더 검사 {} · 대기 {} · 경계 제외 {}",
                        p.folders,
                        p.pending,
                        p.excluded
                            .map(|n| n.to_string())
                            .unwrap_or_else(|| "완료 후 확인".into())
                    ))
                    .child(p.current.clone());
                if p.errors > 0 {
                    progress = progress.child(format!(
                        "접근 오류 {}개 · 읽을 수 있는 항목은 계속 검사합니다",
                        p.errors
                    ));
                }
            }
            center = center.child(progress);
        }
        if !self.filter_error.is_empty() {
            center = center.child(
                div()
                    .p_2()
                    .text_color(rgb(0xecaa74))
                    .child(self.filter_error.clone()),
            );
        }
        if !self.scanning
            && self.projection_rx.is_none()
            && self.filter_error.is_empty()
            && self
                .projection
                .as_ref()
                .is_some_and(|p| p.children.is_empty())
            && self.focus_node_is_directory()
        {
            self.geometry.borrow_mut().suspend();
            self.tiles.borrow_mut().clear();
            center = center.child(
                div()
                    .flex_1()
                    .flex()
                    .flex_col()
                    .justify_center()
                    .items_center()
                    .gap_3()
                    .text_color(rgb(MUTED))
                    .child("표시할 항목이 없습니다.")
                    .child(self.button(
                        "clear-filter",
                        "필터 지우기",
                        Command::ClearFilter,
                        true,
                        cx,
                    )),
            );
        } else if self.list_mode && !self.scanning && self.projection.is_some() {
            self.geometry.borrow_mut().suspend();
            self.tiles.borrow_mut().clear();
            let rows = self.projection.as_ref().map_or(0, |p| p.children.len());
            center = center.child(
                uniform_list(
                    "details-list",
                    rows,
                    cx.processor(|this, range: std::ops::Range<usize>, _, cx| {
                        range.map(|i| this.row(i, cx)).collect::<Vec<_>>()
                    }),
                )
                .flex_1(),
            );
        } else {
            center = center.child(div().flex_1().min_h_0().child(self.mosaic(cx)));
        }
        center
            .child(
                div()
                    .h(px(30.))
                    .flex_shrink_0()
                    .px(px(18.))
                    .flex()
                    .items_center()
                    .gap_3()
                    .text_size(px(9.))
                    .text_color(rgb(MUTED))
                    .child("● 이미지")
                    .child("● 동영상")
                    .child("● 음악")
                    .child("● 압축 파일")
                    .child("● 코드")
                    .child("● 문서")
                    .child(div().flex_1())
                    .child("더블 클릭: 확대 · 우클릭: 작업"),
            )
            .into_any_element()
    }
}
impl Explorer {
    fn context_actions(&self, position: Point<Pixels>, cx: &mut Context<Self>) -> AnyElement {
        let mut menu = div()
            .id("context-menu")
            .w(px(220.))
            .p_2()
            .rounded_md()
            .bg(rgb(0x22282d))
            .border_1()
            .border_color(rgb(BORDER))
            .shadow_lg()
            .flex()
            .flex_col()
            .text_size(px(11.))
            .occlude()
            .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                this.context_menu = None;
                cx.notify();
            }));
        for (id, label, command, enabled) in [
            ("ctx-open", "열기", Command::Open, true),
            (
                "ctx-reveal",
                crate::platform::reveal_label(),
                Command::Reveal,
                !self.offline,
            ),
            ("ctx-copy", "경로 복사", Command::CopyPath, true),
            (
                "ctx-preview",
                "빠른 보기",
                Command::Preview,
                !self.offline && crate::platform::preview_supported(),
            ),
            ("ctx-red", "🔴 빨강", Command::Tag(1), true),
            ("ctx-yellow", "🟡 노랑", Command::Tag(2), true),
            ("ctx-green", "🟢 초록", Command::Tag(3), true),
            ("ctx-blue", "🔵 파랑", Command::Tag(4), true),
            ("ctx-clear", "태그 해제", Command::Tag(0), true),
            (
                "ctx-trash",
                "휴지통으로 이동…",
                Command::Trash,
                !self.offline && !self.scanning && self.selected != Some(0),
            ),
        ] {
            menu = menu.child(self.button(id, label, command, enabled, cx));
        }
        deferred(anchored().position(position).child(menu))
            .with_priority(10)
            .into_any_element()
    }
}
impl Render for Explorer {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let mut body = div().flex_1().min_h_0().flex().child(self.sidebar(cx));
        if self.snapshot.is_none() && !self.scanning {
            body = body.child(self.welcome(cx));
        } else {
            body = body.child(self.workspace(cx));
        }
        if self.snapshot.is_some() {
            body = body.child(self.inspector(cx));
        }
        div()
            .relative()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                this.keyboard(event, window, cx)
            }))
            .on_drop(cx.listener(|this, paths: &ExternalPaths, window, cx| {
                if let Some(path) = paths.paths().first() {
                    this.open_location(path.clone(), window, cx)
                }
            }))
            .size_full()
            .flex()
            .flex_col()
            .bg(rgb(BG))
            .text_color(rgb(TEXT))
            .font_family("Noto Sans KR")
            .text_size(px(12.))
            .child(
                div()
                    .h(px(48.))
                    .flex_shrink_0()
                    .pl(px(crate::platform::header_inset()))
                    .pr(px(18.))
                    .bg(rgb(SURFACE))
                    .border_b_1()
                    .border_color(rgb(BORDER))
                    .flex()
                    .items_center()
                    .gap_3()
                    .child(
                        div()
                            .text_color(rgb(ACCENT))
                            .text_size(px(20.))
                            .child(icon("grid-2x2", 18.).text_color(rgb(ACCENT))),
                    )
                    .child(
                        div()
                            .text_size(px(14.))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child("Mac Space Sniffer"),
                    )
                    .child(
                        div()
                            .text_size(px(9.))
                            .text_color(rgb(MUTED))
                            .child("D I S K  E X P L O R E R"),
                    )
                    .child(
                        div()
                            .flex_1()
                            .h_full()
                            .window_control_area(WindowControlArea::Drag),
                    )
                    .children((self.scanning && !cx.reduce_motion()).then(|| {
                        icon("loader-circle", 14.)
                            .text_color(rgb(ACCENT))
                            .with_animation(
                                "scan-spinner",
                                Animation::new(std::time::Duration::from_secs(1)).repeat(),
                                |svg, delta| {
                                    svg.with_transformation(Transformation::rotate(radians(
                                        delta * std::f32::consts::TAU,
                                    )))
                                },
                            )
                    }))
                    .child(div().text_size(px(11.)).text_color(rgb(ACCENT)).child(
                        if self.scanning {
                            "디스크 읽는 중"
                        } else if self.offline {
                            "▣ 스냅샷"
                        } else {
                            ""
                        },
                    ))
                    .child(
                        self.button("choose", "▣ 폴더 스캔", Command::Browse, true, cx)
                            .bg(rgb(ACCENT))
                            .text_color(rgb(BG))
                            .text_size(px(11.)),
                    )
                    .child(self.popup("more", "⊙", Command::More, self.more_menu, 2, cx)),
            )
            .child(body)
            .child(
                div()
                    .h(px(31.))
                    .flex_shrink_0()
                    .px(px(18.))
                    .border_t_1()
                    .border_color(rgb(BORDER))
                    .bg(rgb(SURFACE))
                    .flex()
                    .items_center()
                    .gap_2()
                    .text_size(px(10.))
                    .text_color(rgb(MUTED))
                    .child(div().text_color(rgb(ACCENT)).child("●"))
                    .child(self.status.clone())
                    .child(div().flex_1())
                    .child(self.button(
                        "issues",
                        "접근 오류",
                        Command::Issues,
                        self.snapshot.is_some(),
                        cx,
                    ))
                    .child("로컬 분석"),
            )
            .children(self.issues_sheet(cx))
            .children(self.document_choice_view(cx))
            .children(self.error_dialog.as_ref().map(|error| {
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
                            .w(px(560.))
                            .max_h(px(500.))
                            .p_5()
                            .rounded_lg()
                            .bg(rgb(SURFACE))
                            .flex()
                            .flex_col()
                            .gap_3()
                            .child(div().text_lg().child("작업을 완료하지 못했습니다"))
                            .child(
                                div()
                                    .id("error-message")
                                    .max_h(px(320.))
                                    .overflow_y_scroll()
                                    .child(error.clone()),
                            )
                            .child(self.button(
                                "dismiss-error",
                                "확인",
                                Command::DismissError,
                                true,
                                cx,
                            )),
                    )
            }))
            .children(
                self.context_menu
                    .map(|position| self.context_actions(position, cx)),
            )
    }
}
