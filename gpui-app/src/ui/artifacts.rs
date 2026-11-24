use super::app::Explorer;
use crate::{
    backend::{Event, ScanSession},
    model::Snapshot,
    platform,
};
use gpui_kit::*;
use std::path::PathBuf;
impl Explorer {
    pub(super) fn save(&mut self, report: bool, window: &mut Window, cx: &mut Context<Self>) {
        let Some(source) = self.snapshot.clone() else {
            return;
        };
        let Some(document) = source.document.clone() else {
            self.status =
                "이전 JSON 스냅샷은 SNS 문서 기능을 지원하지 않습니다. 폴더를 다시 분석하세요."
                    .into();
            return;
        };
        let command = serde_json::json!({"operation":if report {"report"} else {"sns"},
            "root":self.focus, "filter":self.filter_input.read(cx).value().to_string(),
            "logical":self.mode == crate::projection::SizeMode::Logical,"hidden":self.hidden,"tags":self.tags});
        let chosen = cx.prompt_for_new_path(
            &std::env::home_dir().unwrap_or_default(),
            Some(if report {
                "SpaceSniffer.txt"
            } else {
                "SpaceSniffer.sns"
            }),
        );
        cx.spawn_in(window, async move |this, cx| {
            if let Ok(Ok(Some(path))) = chosen.await {
                let display = path.clone();
                let result = cx
                    .background_executor()
                    .spawn(async move { crate::document::save_atomic(&document, command, &path) })
                    .await;
                let _ = this.update(cx, |this, cx| {
                    this.status = match result {
                        Ok(()) => format!("저장 완료: {}", display.display()),
                        Err(e) => {
                            this.error_dialog = Some(e.to_string());
                            format!("저장 오류: {e}")
                        }
                    };
                    cx.notify();
                });
            }
        })
        .detach();
    }
    pub(super) fn load(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let chosen = cx.prompt_for_paths(PathPromptOptions {
            files: true,
            directories: false,
            multiple: false,
            prompt: Some("SNS · DU · JSON 스냅샷 열기".into()),
        });
        cx.spawn_in(window, async move |this, cx| {
            let Ok(Ok(Some(paths))) = chosen.await else {
                return;
            };
            let Some(path) = paths.into_iter().next() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                this.open_snapshot_file(path, window, cx)
            });
        })
        .detach();
    }
    pub(super) fn open_snapshot_file(
        &mut self,
        path: PathBuf,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.cancel_import();
        let request = self.document_open_id;
        cx.spawn_in(window, async move |this, cx| {
            let result = if path
                .extension()
                .is_some_and(|x| x.eq_ignore_ascii_case("json"))
            {
                cx.background_executor()
                    .spawn(async move { Snapshot::load(&path).map(|s| (s, None)) })
                    .await
            } else {
                let started = cx
                    .background_executor()
                    .spawn(async move { ScanSession::open(&platform::backend(), &path) })
                    .await;
                match started {
                    Err(e) => Err(e),
                    Ok(mut session) => {
                        let accepted = this
                            .update(cx, |this, _| {
                                if this.document_open_id != request {
                                    return false;
                                }
                                this.pending_import = Some(session.process_handle());
                                true
                            })
                            .unwrap_or(false);
                        if !accepted {
                            session.process_handle().shutdown();
                            return;
                        }
                        loop {
                            let (returned, event) = cx
                                .background_executor()
                                .spawn(async move {
                                    let event = session.events.recv();
                                    (session, event)
                                })
                                .await;
                            session = returned;
                            if this
                                .update(cx, |this, _| this.document_open_id != request)
                                .unwrap_or(true)
                            {
                                return;
                            }
                            match event {
                                Ok(Event::Complete(source)) => break Ok((source, Some(session))),
                                Ok(Event::ImportRoots(roots)) => {
                                    let prompt = this.update_in(cx, |this, window, cx| {
                                        window.focus(&this.focus_handle, cx);
                                        this.ask_document_choice(
                                            "열 스냅샷 루트를 선택하세요",
                                            roots,
                                            cx,
                                        )
                                    });
                                    let Ok(prompt) = prompt else {
                                        return;
                                    };
                                    match prompt.await {
                                        Ok(Some(index)) => session.send(&format!("select {index}")),
                                        _ => return,
                                    }
                                }
                                Ok(Event::ImportCodePage) => {
                                    use super::document_choices::LEGACY_ENCODINGS;
                                    let prompt = this.update_in(cx, |this, window, cx| {
                                        window.focus(&this.focus_handle, cx);
                                        this.ask_document_choice(
                                            "저장한 Windows의 코드 페이지를 선택하세요",
                                            LEGACY_ENCODINGS
                                                .iter()
                                                .map(|(label, _)| label.to_string())
                                                .collect(),
                                            cx,
                                        )
                                    });
                                    let Ok(prompt) = prompt else {
                                        return;
                                    };
                                    match prompt.await {
                                        Ok(Some(index)) => session.send(&format!(
                                            "codepage {}",
                                            LEGACY_ENCODINGS[index].1
                                        )),
                                        _ => return,
                                    }
                                }
                                Ok(Event::Failure(e)) => break Err(anyhow::anyhow!(e)),
                                Err(e) => break Err(anyhow::anyhow!(e)),
                                _ => {}
                            }
                        }
                    }
                }
            };
            let _ = this.update_in(cx, |this, window, cx| {
                if this.document_open_id != request {
                    return;
                }
                this.pending_import = None;
                match result {
                    Ok((source, session)) => {
                        this.install_snapshot(source, session, window, cx);
                    }
                    Err(e) => {
                        this.error_dialog = Some(e.to_string());
                        this.status = format!("스냅샷 오류: {e}");
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }
}

impl Explorer {
    pub(super) fn install_snapshot(
        &mut self,
        source: std::sync::Arc<Snapshot>,
        session: Option<ScanSession>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.error_dialog = None;
        self.reset_workspace(PathBuf::from(&source.root));
        self.root = PathBuf::from(&source.root);
        self.scanning = false;
        self.progress = None;
        self.projection = None;
        self.session = session;
        self.monitor = None;
        self.native_watch_active = false;
        self.changed = None;
        self.tags = source.tags.clone();
        self.snapshot = Some(source);
        self.offline = true;
        self.focus = 0;
        self.selected = None;
        self.hovered = None;
        self.history.clear();
        self.future.clear();
        self.tiles.borrow_mut().clear();
        self.path_input.update(cx, |input, cx| {
            input.set_value(self.root.to_string_lossy().to_string(), window, cx)
        });
        self.filter_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.filter_error.clear();
        self.status = "오프라인 스냅샷".into();
        self.refresh(cx);
    }
}

impl Explorer {
    pub(super) fn cancel_import(&mut self) {
        self.document_open_id = self.document_open_id.wrapping_add(1);
        self.finish_document_choice(None);
        if let Some(process) = self.pending_import.take() {
            process.shutdown();
        }
    }
}
