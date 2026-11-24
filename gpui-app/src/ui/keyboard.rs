use super::app::{Command, Explorer};
use gpui_kit::*;
impl Explorer {
    pub fn keyboard(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let key = event.keystroke.key.as_str();
        let m = event.keystroke.modifiers;
        if m.secondary() && matches!(key, "q" | "w") {
            self.command(
                if key == "q" {
                    Command::Quit
                } else {
                    Command::CloseWindow
                },
                window,
                cx,
            );
            cx.stop_propagation();
            return;
        }
        if self.error_dialog.is_some() {
            if key == "escape" || key == "enter" {
                self.command(Command::DismissError, window, cx);
            }
            cx.stop_propagation();
            return;
        }
        if self.show_issues {
            if key == "escape" || key == "enter" {
                self.command(Command::Issues, window, cx);
            }
            cx.stop_propagation();
            return;
        }
        if self.document_choice.is_some() {
            if key == "escape" {
                self.command(Command::ChooseDocument(None), window, cx);
            }
            cx.stop_propagation();
            return;
        }
        if !m.secondary()
            && !m.alt
            && self.focus_handle.is_focused(window)
            && let Ok(color) = key.parse::<u8>()
            && (1..=4).contains(&color)
            && let Some(id) = self.hovered.or(self.selected)
        {
            self.tag_node(id, color, cx);
            cx.stop_propagation();
            return;
        }
        let command = if m.secondary() {
            match (key, m.shift) {
                ("q", _) => Some(Command::Quit),
                ("w", _) => Some(Command::CloseWindow),
                ("m", _) => Some(Command::Minimize),
                ("h", false) => Some(Command::HideWindow),
                ("n", _) => Some(Command::NewWindow),
                ("o", true) => Some(Command::Load),
                ("o", false) => Some(Command::Browse),
                ("s", _) => Some(Command::Save),
                ("e", _) => Some(Command::Export),
                ("[", _) => Some(Command::Back),
                ("]", _) => Some(Command::Forward),
                ("up", _) => Some(Command::Up),
                ("h", true) => Some(Command::Root),
                ("r", true) => Some(Command::RescanFocus),
                ("r", false) => Some(Command::Rescan),
                (".", _) => Some(Command::Cancel),
                ("f", true) => Some(Command::Reveal),
                ("backspace", _) => Some(Command::Trash),
                _ => None,
            }
        } else if self.focus_handle.is_focused(window) {
            match key {
                "enter" => Some(Command::ZoomSelected),
                "space" => Some(Command::Preview),
                "escape" => {
                    self.selected = None;
                    self.context_menu = None;
                    cx.notify();
                    None
                }
                "1" => self.selected.map(|_| Command::Tag(1)),
                "2" => self.selected.map(|_| Command::Tag(2)),
                "3" => self.selected.map(|_| Command::Tag(3)),
                "4" => self.selected.map(|_| Command::Tag(4)),
                "0" => Some(Command::ClearTags),
                "backspace" => Some(if m.shift {
                    Command::Forward
                } else {
                    Command::Back
                }),
                "left" | "right" | "up" | "down" => {
                    if let Some(p) = &self.projection {
                        if !p.children.is_empty() {
                            let current = self
                                .selected
                                .and_then(|id| p.children.iter().position(|&i| i == id));
                            let index = current.map_or(0, |i| {
                                if key == "left" || key == "up" {
                                    (i + p.children.len() - 1) % p.children.len()
                                } else {
                                    (i + 1) % p.children.len()
                                }
                            });
                            Some(Command::Select(p.children[index]))
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                }
                _ => None,
            }
        } else {
            None
        };
        if let Some(command) = command {
            cx.stop_propagation();
            self.command(command, window, cx)
        }
    }
}
