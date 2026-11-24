use super::app::Explorer;
use gpui_kit::*;
impl Explorer {
    pub(super) fn preview_selected(&mut self, cx: &mut Context<Self>) {
        if self.offline {
            return;
        }
        let Some(path) = self.selected.and_then(|id| {
            self.snapshot
                .as_ref()
                .and_then(|source| source.nodes.get(id))
                .map(|node| std::path::PathBuf::from(&node.path))
        }) else {
            return;
        };
        // Native UI can pump a nested event loop. Run after the event listener
        // releases GPUI's App/Explorer borrows, on the same foreground executor.
        cx.spawn(async move |this, cx| {
            if this.upgrade().is_none() {
                return;
            }
            if let Err(error) = crate::platform::preview(&path) {
                let _ = this.update(cx, |app, cx| {
                    app.status = format!("미리보기 오류: {error}");
                    cx.notify();
                });
            }
        })
        .detach();
    }

    pub fn tag_for(&self, id: usize) -> u8 {
        let Some(source) = &self.snapshot else {
            return 0;
        };
        source
            .nodes
            .get(id)
            .and_then(|n| self.tags.get(&n.path))
            .copied()
            .unwrap_or(0)
    }
    pub(super) fn tag_node(&mut self, id: usize, color: u8, cx: &mut Context<Self>) {
        if color > 4 {
            return;
        }
        if let Some(node) = self.snapshot.as_ref().and_then(|s| s.nodes.get(id)) {
            let bit = if color == 0 { 0 } else { 1 << (color - 1) };
            if bit == 0 || self.tags.get(&node.path).copied().unwrap_or(0) == bit {
                self.tags.remove(&node.path);
            } else {
                self.tags.insert(node.path.clone(), bit);
            }
            self.projection = None;
            self.refresh(cx);
        }
    }
    pub fn trash(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.offline || self.scanning {
            return;
        }
        let id = self.selected.unwrap_or(self.focus);
        if id == 0 {
            return;
        }
        let Some(n) = self.snapshot.as_ref().and_then(|s| s.nodes.get(id)) else {
            return;
        };
        let path = std::path::PathBuf::from(&n.path);
        let answer = window.prompt(
            PromptLevel::Warning,
            "휴지통으로 이동할까요?",
            Some(&n.path),
            &[
                PromptButton::cancel("취소"),
                PromptButton::ok("휴지통으로 이동"),
            ],
            cx,
        );
        cx.spawn_in(window, async move |this, cx| {
            if answer.await == Ok(1) {
                let result = cx
                    .background_executor()
                    .spawn(async move { trash::delete(&path) })
                    .await;
                let _ = this.update_in(cx, |app, window, cx| match result {
                    Ok(()) => app.command(super::app::Command::Rescan, window, cx),
                    Err(e) => {
                        app.status = format!("휴지통 이동 오류: {e}");
                        cx.notify();
                    }
                });
            }
        })
        .detach();
    }
}
