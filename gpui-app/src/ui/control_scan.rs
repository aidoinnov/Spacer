//! Validate a new scan completely, then apply its options before starting I/O.
use super::app::Explorer;
use gpui_kit::{Context, Window};
use serde::Deserialize;
use serde_json::{Value, json};
use std::path::PathBuf;

#[derive(Deserialize)]
struct Start {
    path: PathBuf,
    watching: Option<bool>,
    include_mounted_volumes: Option<bool>,
    #[serde(default)]
    replace: bool,
}
impl Start {
    fn parse(args: &Value) -> anyhow::Result<Self> {
        let value: Self = serde_json::from_value(args.clone())?;
        anyhow::ensure!(value.path.is_absolute(), "invalid_argument");
        Ok(value)
    }
}

pub(super) fn start(
    app: &mut Explorer,
    args: &Value,
    window: &mut Window,
    cx: &mut Context<Explorer>,
) -> anyhow::Result<Value> {
    let request = Start::parse(args)?;
    anyhow::ensure!(!app.scanning || request.replace, "scan_active");
    anyhow::ensure!(
        request.include_mounted_volumes != Some(true)
            || crate::platform::mounted_volumes_supported(),
        "unsupported_scope"
    );
    if let Some(watching) = request.watching {
        app.watching = watching;
    }
    if let Some(include) = request.include_mounted_volumes {
        app.include_mounted = include;
    }
    app.choose(request.path, window, cx);
    Ok(json!({"accepted":true}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_options_preserve_explicit_false_and_omitted_values() {
        let root = std::env::temp_dir();
        let request =
            Start::parse(&json!({"path":root,"watching":false,"include_mounted_volumes":false}))
                .unwrap();
        assert_eq!(request.watching, Some(false));
        assert_eq!(request.include_mounted_volumes, Some(false));
        let inherited = Start::parse(&json!({"path":root})).unwrap();
        assert_eq!(inherited.watching, None);
        assert_eq!(inherited.include_mounted_volumes, None);
        assert!(!inherited.replace);
    }

    #[test]
    fn scan_request_rejects_relative_paths_and_malformed_options() {
        let root = std::env::temp_dir();
        for request in [
            json!({"path":"relative"}),
            json!({"path":root,"watching":"true"}),
            json!({"path":root,"include_mounted_volumes":1}),
            json!({"path":root,"replace":"yes"}),
        ] {
            assert!(Start::parse(&request).is_err());
        }
    }
}
