use super::app::Explorer;
use crate::{backend::ScanSession, platform};
use gpui_kit::*;
impl Explorer {
    /// Whole rescans belong to the original document; focus rescans preserve siblings.
    pub(super) fn request_rescan(&mut self, focused: bool, cx: &mut Context<Self>) {
        if self.offline {
            return;
        }
        if !focused && self.root != self.workspace.scope {
            if let Some(document) = self.workspace.parked.get_mut(&self.workspace.scope) {
                if document.scanning {
                    return;
                }
                if let Some(session) = &document.session {
                    session.send("rescan");
                    document.scanning = true;
                } else {
                    match ScanSession::start_scoped(
                        &platform::backend(),
                        &document.root,
                        self.watching,
                        self.include_mounted,
                    ) {
                        Ok(session) => {
                            document.session = Some(session);
                            document.scanning = true;
                        }
                        Err(e) => self.status = e.to_string(),
                    }
                }
            }
            return;
        }
        if self.scanning {
            return;
        }
        if self
            .session
            .as_ref()
            .is_some_and(|session| !session.is_alive())
        {
            self.session = None;
        }
        if let Some(session) = &self.session {
            session.send(&if focused {
                super::control_rescan::command(&self.root, &self.focus_path())
            } else {
                "rescan".into()
            });
            self.scanning = true;
            self.progress = None;
            self.status = "다시 분석 중".into();
            cx.notify();
        } else {
            self.start(cx)
        }
    }
}
