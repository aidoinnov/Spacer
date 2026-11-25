//! Native document orchestration; no UI, filesystem traversal, or filter fork.
use crate::{
    backend::{Event, ScanSession},
    document::NativeDocument,
    options::Options,
};
use anyhow::{Context, Result, bail, ensure};
use base64::Engine;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    io::Read,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Debug)]
pub struct Cancelled;
impl std::fmt::Display for Cancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Cancelled")
    }
}
impl std::error::Error for Cancelled {}

struct OwnedSession {
    session: ScanSession,
    stop: Arc<AtomicBool>,
    watcher: Option<thread::JoinHandle<()>>,
}
impl OwnedSession {
    fn new(session: ScanSession, cancelled: Arc<AtomicBool>) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let stopped = stop.clone();
        let process = session.process_handle();
        let watcher = thread::spawn(move || {
            while !stopped.load(Ordering::Relaxed) {
                if cancelled.load(Ordering::Relaxed) {
                    process.send("cancel");
                    let deadline = Instant::now() + Duration::from_secs(5);
                    while !stopped.load(Ordering::Relaxed) && Instant::now() < deadline {
                        thread::sleep(Duration::from_millis(20));
                    }
                    if !stopped.load(Ordering::Relaxed) {
                        process.shutdown();
                    }
                    return;
                }
                thread::sleep(Duration::from_millis(20));
            }
        });
        Self {
            session,
            stop,
            watcher: Some(watcher),
        }
    }
}
impl Drop for OwnedSession {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(watcher) = self.watcher.take() {
            let _ = watcher.join();
        }
        let process = self.session.process_handle();
        process.shutdown();
        let deadline = Instant::now() + Duration::from_secs(8);
        loop {
            let mut child = process.child.lock().unwrap();
            if child.try_wait().map_or(true, |s| s.is_some()) {
                break;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                break;
            }
            drop(child);
            thread::sleep(Duration::from_millis(20));
        }
    }
}

fn configuration(options: &Options, key: &str) -> Result<Value> {
    let path = options.path(key).context("Configuration path missing")?;
    ensure!(
        std::fs::metadata(&path)?.is_file(),
        "Configuration is not a regular file"
    );
    let mut xml = Vec::new();
    std::fs::File::open(path)?
        .take(4_194_305)
        .read_to_end(&mut xml)?;
    ensure!(xml.len() <= 4_194_304, "Configuration exceeds 4 MiB");
    Ok(
        json!({"configuration":base64::engine::general_purpose::STANDARD.encode(xml),
        "codePage":options.number("--config-xml-code-page")?.or(options.number("--config-legacy-code-page")?)}),
    )
}

pub fn execute(options: Options) -> Result<(Value, i32)> {
    let cancelled = Arc::new(AtomicBool::new(false));
    let signal = cancelled.clone();
    ctrlc::set_handler(move || signal.store(true, Ordering::Relaxed))?;
    if options.has("--parent-stdio") {
        let signal = cancelled.clone();
        thread::spawn(move || {
            let mut byte = [0];
            while matches!(std::io::stdin().read(&mut byte),Ok(n) if n>0) {}
            signal.store(true, Ordering::Relaxed);
        });
    }
    let result = operation(&options, cancelled.clone());
    if cancelled.load(Ordering::Relaxed) {
        match result {
            Ok((mut summary, _)) => {
                summary["cancelled"] = true.into();
                Ok((summary, 130))
            }
            Err(_) => Err(Cancelled.into()),
        }
    } else {
        result
    }
}

fn operation(options: &Options, cancelled: Arc<AtomicBool>) -> Result<(Value, i32)> {
    let backend = crate::process::backend();
    ensure!(
        backend.is_file(),
        "Native backend not found: {} (set SNIFFER_SCAN_BACKEND)",
        backend.display()
    );
    if options.path("--inspect-config").is_some() {
        let owner = OwnedSession::new(ScanSession::documents(&backend)?, cancelled);
        let document = NativeDocument {
            process: owner.session.process_handle(),
            version: "metadata".into(),
        };
        let mut command = configuration(options, "--inspect-config")?;
        command["operation"] = "exportConfigurations".into();
        let mut output = Vec::new();
        document.request(command, &mut output)?;
        return Ok((
            json!({"exports":serde_json::from_slice::<Value>(&output)?}),
            0,
        ));
    }
    let session = if let Some(path) = options.path("--scan") {
        ensure!(path.is_dir(), "Not a directory: {}", path.display());
        ScanSession::start_scoped(
            &backend,
            &crate::paths::scan_path(&path),
            false,
            options.has("--include-mounted-volumes"),
        )?
    } else {
        let path = options.path("--load").context("Missing input")?;
        if options.has("--list-roots") {
            ScanSession::inspect(&backend, &path)?
        } else {
            ScanSession::open(&backend, &path)?
        }
    };
    let owner = OwnedSession::new(session, cancelled.clone());
    let mut selected = false;
    let source = loop {
        match owner
            .session
            .events
            .recv_timeout(Duration::from_millis(100))
        {
            Ok(Event::Complete(source)) => {
                ensure!(
                    selected || options.number("--snapshot-root-index")?.unwrap_or(0) == 0,
                    "Invalid root index"
                );
                break source;
            }
            Ok(Event::ImportCodePage) => {
                let page = options
                    .number("--legacy-code-page")?
                    .context("--legacy-code-page is required for this file")?;
                owner.session.send(&format!("codepage {page}"));
            }
            Ok(Event::ImportRoots(roots)) => {
                let index = usize::try_from(
                    options
                        .number("--snapshot-root-index")?
                        .context("--snapshot-root-index is required for multiple roots")?,
                )?;
                ensure!(index < roots.len(), "Invalid root index");
                owner.session.send(&format!("select {index}"));
                selected = true;
            }
            Ok(Event::ImportInspection(mut roots)) => {
                if let Some(rows) = roots.as_array_mut() {
                    for row in rows {
                        row["root_index"] = row["index"].clone();
                    }
                }
                return Ok((json!({"roots":roots}), 0));
            }
            Ok(Event::Failure(error)) => bail!(error),
            Ok(_) => {}
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
            Err(error) => return Err(error.into()),
        }
    };
    let document = source
        .document
        .as_ref()
        .context("Native document unavailable")?;
    let filter = options.text("--filter")?.unwrap_or("");
    let tags: HashMap<String, u8> = source.tags.clone();
    let weights = document.weights(
        filter,
        options.has("--logical"),
        !options.has("--hide-hidden"),
        &tags,
        source.nodes.len(),
    )?;
    if !cancelled.load(Ordering::Relaxed)
        && !source.cancelled
        && let Some(path) = options.path("--output")
    {
        let mut command = json!({"operation":if path.extension().is_some_and(|e| e.eq_ignore_ascii_case("sns")){"sns"}else{"report"},
                "root":0,"filter":filter,"logical":options.has("--logical"),"hidden":!options.has("--hide-hidden"),"tags":tags});
        if options.path("--export-config").is_some() {
            let config = configuration(options, "--export-config")?;
            command["operation"] = "configuredReport".into();
            command["configuration"] = config["configuration"].clone();
            command["codePage"] = config["codePage"].clone();
            command["configurationIndex"] =
                options.number("--export-config-index")?.unwrap_or(0).into();
            command["maxOutputBytes"] = options
                .number("--max-output-bytes")?
                .unwrap_or(1_073_741_824)
                .into();
        }
        crate::document::save_new_atomic(document, command, &path)?;
    }
    let mut summary = json!({"root":source.root,"files":source.files,"folders":source.folders,
        "logicalBytes":source.nodes[0].logical,"allocatedBytes":source.nodes[0].allocated,
        "matchedBytes":weights[0],"issues":source.errors,"cancelled":source.cancelled,
        "volume_traversal":source.volume_traversal,"excluded_boundary_count":source.excluded});
    if options.has("--issues") {
        summary["issue_details"] = json!(source.issues);
        summary["stored_issues"] = json!(source.issues.len());
    }
    Ok((
        summary,
        if source.cancelled {
            130
        } else if source.errors > 0 {
            2
        } else {
            0
        },
    ))
}
