use super::{
    app::{Command, Explorer},
    theme::*,
};
use futures::channel::oneshot;
use gpui_kit::*;

pub const LEGACY_ENCODINGS: &[(&str, u32)] = &[
    ("한국어 (Windows 949)", 949),
    ("일본어 (Windows 932)", 932),
    ("중국어 간체 (Windows 936)", 936),
    ("중국어 번체 (Windows 950)", 950),
    ("서유럽 (Windows 1252)", 1252),
    ("중부 유럽 (Windows 1250)", 1250),
    ("키릴 문자 (Windows 1251)", 1251),
    ("그리스어 (Windows 1253)", 1253),
    ("터키어 (Windows 1254)", 1254),
    ("히브리어 (Windows 1255)", 1255),
    ("아랍어 (Windows 1256)", 1256),
    ("발트어 (Windows 1257)", 1257),
    ("베트남어 (Windows 1258)", 1258),
    ("태국어 (Windows 874)", 874),
    ("UTF-8", 65001),
];
pub(super) struct DocumentChoice {
    title: String,
    choices: Vec<String>,
    result: oneshot::Sender<Option<usize>>,
}
impl Explorer {
    pub(super) fn ask_document_choice(
        &mut self,
        title: &str,
        choices: Vec<String>,
        cx: &mut Context<Self>,
    ) -> oneshot::Receiver<Option<usize>> {
        let (result, receiver) = oneshot::channel();
        self.document_choice = Some(DocumentChoice {
            title: title.into(),
            choices,
            result,
        });
        cx.notify();
        receiver
    }
    pub(super) fn finish_document_choice(&mut self, choice: Option<usize>) {
        if let Some(prompt) = self.document_choice.take() {
            let choice = choice.filter(|&i| i < prompt.choices.len());
            let _ = prompt.result.send(choice);
        }
    }
    pub(super) fn document_choice_view(&self, cx: &mut Context<Self>) -> Option<AnyElement> {
        let prompt = self.document_choice.as_ref()?;
        Some(
            div()
                .absolute()
                .inset_0()
                .flex()
                .items_center()
                .justify_center()
                .bg(rgba(0x00000099))
                .child(
                    div()
                        .w(px(600.))
                        .p_5()
                        .flex()
                        .flex_col()
                        .gap_3()
                        .rounded_lg()
                        .bg(rgb(SURFACE))
                        .border_1()
                        .border_color(rgb(BORDER))
                        .child(div().text_size(px(16.)).child(prompt.title.clone()))
                        .child(
                            uniform_list(
                                "document-choices",
                                prompt.choices.len(),
                                cx.processor(|this, range: std::ops::Range<usize>, _, cx| {
                                    range
                                        .map(|index| {
                                            let text =
                                                this.document_choice.as_ref().unwrap().choices
                                                    [index]
                                                    .clone();
                                            div()
                                                .id(("document-choice", index))
                                                .h(px(36.))
                                                .px_3()
                                                .flex()
                                                .items_center()
                                                .overflow_hidden()
                                                .cursor_pointer()
                                                .hover(|style| style.bg(rgb(0x26343c)))
                                                .child(text)
                                                .on_click(cx.listener(
                                                    move |this, _, window, cx| {
                                                        this.command(
                                                            Command::ChooseDocument(Some(index)),
                                                            window,
                                                            cx,
                                                        )
                                                    },
                                                ))
                                        })
                                        .collect::<Vec<_>>()
                                }),
                            )
                            .h(px(320.)),
                        )
                        .child(self.button(
                            "cancel-document-choice",
                            "취소",
                            Command::ChooseDocument(None),
                            true,
                            cx,
                        )),
                )
                .into_any_element(),
        )
    }
}
