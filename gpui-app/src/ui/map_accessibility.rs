//! Bounded virtual map children, keyed by current path rather than transient node ID.
use super::app::{Command, Explorer};
use crate::{
    layout::Tile,
    model::{Snapshot, bytes},
};
use gpui_kit::*;
pub(super) type Actions = std::rc::Rc<std::cell::RefCell<Vec<(accesskit::NodeId, String)>>>;
pub(super) fn publish(
    builder: &mut A11ySubtreeBuilder,
    tiles: &[Tile],
    source: &Snapshot,
    focus: usize,
    scale: f32,
    actions: &Actions,
) {
    let mut actions = actions.borrow_mut();
    actions.clear();
    for tile in tiles.iter().filter(|t| t.interactive && t.opacity > 0.5) {
        let Some(id) = tile.id else { continue };
        let Some(node) = source.nodes.get(id) else {
            continue;
        };
        if node.parent != Some(focus) || node.path != tile.path {
            continue;
        }
        let key = builder.synthetic_node_id(&node.path);
        let mut child = accesskit::Node::new(Role::Button);
        child.set_label(format!("{}, {}", node.name, bytes(tile.weight)));
        let r = tile.rect;
        let s = scale as f64;
        child.set_bounds(accesskit::Rect {
            x0: r.x as f64 * s,
            y0: r.y as f64 * s,
            x1: (r.x + r.w) as f64 * s,
            y1: (r.y + r.h) as f64 * s,
        });
        child.add_action(AccessibleAction::Click);
        if builder.push_child(key, child) {
            actions.push((key, node.path.clone()));
        }
        if actions.len() == 500 {
            break;
        }
    }
}
pub(super) fn install(actions: &Actions, view: &WeakEntity<Explorer>, window: &mut Window) {
    for (id, path) in actions.borrow().iter() {
        let path = path.clone();
        let view = view.clone();
        window.on_a11y_action(*id, AccessibleAction::Click, move |_, window, cx| {
            let _ = view.update(cx, |this, cx| {
                if let Some(id) = this.snapshot.as_ref().and_then(|s| s.node_at_path(&path)) {
                    window.focus(&this.focus_handle, cx);
                    let folder = this
                        .snapshot
                        .as_ref()
                        .is_some_and(|s| s.nodes[id].directory);
                    this.command(
                        if folder {
                            Command::Navigate(id)
                        } else {
                            Command::Select(id)
                        },
                        window,
                        cx,
                    );
                }
            });
        });
    }
}
pub(super) struct MapTip(pub String);
impl Render for MapTip {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("map-tooltip")
            .role(Role::Tooltip)
            .max_w(px(600.))
            .p_3()
            .rounded_md()
            .bg(rgb(super::theme::SURFACE))
            .text_color(rgb(super::theme::TEXT))
            .text_size(px(11.))
            .child(self.0.clone())
    }
}
