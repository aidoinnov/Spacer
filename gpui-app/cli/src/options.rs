use anyhow::{Result, bail, ensure};
use std::{
    collections::{HashMap, HashSet},
    ffi::OsString,
    path::PathBuf,
};

pub const HELP: &str = "Spacer CLI\n\
  --cli --scan PATH [options]        Scan without a window\n\
  --cli --load FILE [options]        Read SNS or DU offline\n\
  --inspect-config FILE             Inspect native export templates\n\
Options:\n\
  --output FILE.txt|FILE.sns         Write a new report/snapshot; never overwrite\n\
  --filter EXPR --logical --hide-hidden --issues\n\
  --include-mounted-volumes         Include nested mounts\n\
  --list-roots --snapshot-root-index N --legacy-code-page N\n\
  --export-config FILE --export-config-index N (default 0)\n\
  --config-xml-code-page N --config-legacy-code-page N\n\
  --max-output-bytes N              Configured export cap (1..1073741824)\n\
  --help --version\n\
Exit: 0 success, 1 error, 2 scan issues, 130 cancellation.\n";

#[derive(Debug)]
pub struct Options {
    pub values: HashMap<String, OsString>,
    pub flags: HashSet<String>,
}
impl Options {
    pub fn parse(args: Vec<OsString>) -> Result<Self> {
        let flags = [
            "--cli",
            "--parent-stdio",
            "--logical",
            "--hide-hidden",
            "--issues",
            "--include-mounted-volumes",
            "--list-roots",
        ];
        let values = [
            "--scan",
            "--load",
            "--output",
            "--filter",
            "--legacy-code-page",
            "--snapshot-root-index",
            "--inspect-config",
            "--export-config",
            "--export-config-index",
            "--config-legacy-code-page",
            "--config-xml-code-page",
            "--max-output-bytes",
        ];
        let mut result = Self {
            values: HashMap::new(),
            flags: HashSet::new(),
        };
        let mut input = args.into_iter();
        while let Some(raw) = input.next() {
            let key = raw
                .to_str()
                .ok_or_else(|| anyhow::anyhow!("Options must be UTF-8"))?;
            ensure!(
                !result.values.contains_key(key) && !result.flags.contains(key),
                "Repeated option: {key}"
            );
            if flags.contains(&key) {
                result.flags.insert(key.into());
            } else if values.contains(&key) {
                let value = input
                    .next()
                    .ok_or_else(|| anyhow::anyhow!("Expected a value for {key}"))?;
                ensure!(
                    !value.to_string_lossy().starts_with("--"),
                    "Expected a value for {key}"
                );
                result.values.insert(key.into(), value);
            } else {
                bail!("Unknown option: {key}");
            }
        }
        ensure!(
            ["--scan", "--load", "--inspect-config"]
                .iter()
                .filter(|k| result.values.contains_key(**k))
                .count()
                == 1,
            "Choose exactly one input: --scan, --load, --inspect-config"
        );
        for key in [
            "--legacy-code-page",
            "--snapshot-root-index",
            "--list-roots",
        ] {
            ensure!(
                !(result.values.contains_key(key) || result.flags.contains(key))
                    || result.path("--load").is_some(),
                "{key} requires --load"
            );
        }
        ensure!(
            !result.has("--list-roots")
                || (result.path("--output").is_none()
                    && result.text("--snapshot-root-index")?.is_none()),
            "--list-roots cannot be combined with output/root selection"
        );
        for key in [
            "--legacy-code-page",
            "--config-legacy-code-page",
            "--config-xml-code-page",
        ] {
            if let Some(n) = result.number(key)? {
                ensure!((1..=65535).contains(&n), "Invalid Windows code page: {key}");
            }
        }
        if let (Some(legacy), Some(xml)) = (
            result.number("--config-legacy-code-page")?,
            result.number("--config-xml-code-page")?,
        ) {
            ensure!(
                legacy == xml,
                "The native document protocol currently requires matching configuration code pages"
            );
        }
        for key in ["--snapshot-root-index", "--export-config-index"] {
            result.number(key)?;
        }
        if let Some(n) = result.number("--max-output-bytes")? {
            ensure!(
                (1..=1_073_741_824).contains(&n),
                "Invalid maximum output bytes"
            );
        }
        let configured = result.path("--export-config").is_some();
        for key in ["--export-config-index", "--max-output-bytes"] {
            ensure!(
                !result.values.contains_key(key) || configured,
                "{key} requires --export-config"
            );
        }
        if let Some(output) = result.path("--output") {
            let extension = output
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("")
                .to_ascii_lowercase();
            ensure!(
                ["sns", "txt"].contains(&extension.as_str()),
                "Output extension must be .txt or .sns"
            );
            ensure!(
                !configured || extension == "txt",
                "Configured exports require .txt output"
            );
            ensure!(
                std::fs::symlink_metadata(output).is_err(),
                "Output already exists"
            );
        } else {
            ensure!(!configured, "--export-config requires --output FILE.txt");
        }
        let inspect = result.path("--inspect-config").is_some();
        for key in ["--config-legacy-code-page", "--config-xml-code-page"] {
            ensure!(
                !result.values.contains_key(key) || inspect || configured,
                "{key} requires configuration input"
            );
        }
        if inspect {
            ensure!(
                result.values.keys().all(|k| [
                    "--inspect-config",
                    "--config-legacy-code-page",
                    "--config-xml-code-page"
                ]
                .contains(&k.as_str()))
                    && result
                        .flags
                        .iter()
                        .all(|k| k == "--cli" || k == "--parent-stdio"),
                "Configuration inspection cannot be combined with scan/export options"
            );
        }
        Ok(result)
    }
    pub fn has(&self, key: &str) -> bool {
        self.flags.contains(key)
    }
    pub fn path(&self, key: &str) -> Option<PathBuf> {
        self.values.get(key).map(PathBuf::from)
    }
    pub fn text(&self, key: &str) -> Result<Option<&str>> {
        self.values
            .get(key)
            .map(|s| {
                s.to_str()
                    .ok_or_else(|| anyhow::anyhow!("{key} must be UTF-8"))
            })
            .transpose()
    }
    pub fn number(&self, key: &str) -> Result<Option<u64>> {
        self.text(key)?
            .map(|s| s.parse().map_err(Into::into))
            .transpose()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_incomplete_ambiguous_or_unknown_inputs() {
        for args in [
            vec!["--scan", "/x", "--filter"],
            vec!["--scan", "/x", "--load", "/s"],
            vec!["--scan", "/x", "--wat"],
            vec!["--scan", "/x", "--scan", "/x"],
            vec!["--scan", "/x", "--legacy-code-page", "0"],
        ] {
            assert!(Options::parse(args.into_iter().map(Into::into).collect()).is_err());
        }
    }
    #[test]
    fn preserves_os_paths_and_empty_filter() {
        let value = Options::parse(
            ["--cli", "--scan", "/한글 folder", "--filter", ""]
                .into_iter()
                .map(Into::into)
                .collect(),
        )
        .unwrap();
        assert_eq!(value.path("--scan"), Some(PathBuf::from("/한글 folder")));
        assert_eq!(value.text("--filter").unwrap(), Some(""));
    }
}
