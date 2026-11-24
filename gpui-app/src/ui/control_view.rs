//! Validate an entire view update before changing the UI or native window.
use super::{
    app::{Command, Explorer},
    control_state::state_with_window,
};
use gpui_kit::*;
use serde::Deserialize;
use serde_json::{Value, json};
#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Size {
    Logical,
    Allocated,
}
#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Action {
    Up,
    Back,
    Forward,
    Root,
}
#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Presentation {
    Normal,
    Minimized,
    Hidden,
}
#[derive(Default, Deserialize)]
struct Update {
    expression: Option<String>,
    size_mode: Option<Size>,
    show_hidden: Option<bool>,
    depth: Option<usize>,
    list_mode: Option<bool>,
    watching: Option<bool>,
    include_mounted: Option<bool>,
    path: Option<std::path::PathBuf>,
    action: Option<Action>,
    width: Option<u32>,
    height: Option<u32>,
    window_state: Option<Presentation>,
}
pub(super) fn apply(
    app: &mut Explorer,
    args: &Value,
    window: &mut Window,
    cx: &mut Context<Explorer>,
) -> anyhow::Result<Value> {
    let update: Update = serde_json::from_value(args.clone())?;
    anyhow::ensure!(
        update.expression.as_ref().is_none_or(|s| s.len() <= 4096),
        "invalid_argument"
    );
    anyhow::ensure!(
        update.depth.is_none_or(|d| (1..=6).contains(&d)),
        "invalid_argument"
    );
    let viewport = window.viewport_size();
    let width = update.width.unwrap_or(f32::from(viewport.width) as u32);
    let height = update.height.unwrap_or(f32::from(viewport.height) as u32);
    if update.width.is_some() || update.height.is_some() {
        anyhow::ensure!(
            (640..=4096).contains(&width) && (480..=4096).contains(&height),
            "invalid_argument"
        );
    }
    if update
        .include_mounted
        .is_some_and(|value| value != app.include_mounted)
    {
        anyhow::ensure!(
            !app.offline && crate::platform::mounted_volumes_supported(),
            "unsupported_scope"
        );
    }
    let revision = app.view_revision;
    let mut projection = false;
    if let Some(expression) = update.expression
        && expression != app.filter_input.read(cx).value().as_ref()
    {
        app.filter_input
            .update(cx, |input, cx| input.set_value(expression, window, cx));
        projection = true;
    }
    if let Some(mode) = update.size_mode {
        let mode = match mode {
            Size::Logical => crate::projection::SizeMode::Logical,
            Size::Allocated => crate::projection::SizeMode::Allocated,
        };
        if app.mode != mode {
            app.mode = mode;
            projection = true;
        }
    }
    if let Some(hidden) = update.show_hidden
        && hidden != app.hidden
    {
        app.hidden = hidden;
        projection = true;
    }
    if let Some(depth) = update.depth {
        app.depth = depth;
    }
    if let Some(list) = update.list_mode {
        app.list_mode = list;
    }
    if let Some(watch) = update.watching
        && watch != app.watching
    {
        app.command(Command::Watch, window, cx);
    }
    if let Some(include) = update.include_mounted
        && include != app.include_mounted
    {
        app.command(Command::MountedVolumes, window, cx);
    }
    if let Some(path) = update.path {
        app.command(Command::NavigatePath(path), window, cx);
    }
    if let Some(action) = update.action {
        app.command(
            match action {
                Action::Up => Command::Up,
                Action::Back => Command::Back,
                Action::Forward => Command::Forward,
                Action::Root => Command::Root,
            },
            window,
            cx,
        );
    }
    if update.width.is_some() || update.height.is_some() {
        window.resize(size(px(width as f32), px(height as f32)));
    }
    if let Some(state) = update.window_state {
        crate::platform::window_state(
            window,
            match state {
                Presentation::Normal => "normal",
                Presentation::Minimized => "minimized",
                Presentation::Hidden => "hidden",
            },
        )?;
    }
    if projection && app.view_revision == revision {
        app.refresh(cx);
    }
    cx.notify();
    Ok(json!({"accepted":true,"state":state_with_window(app,window,cx)}))
}
