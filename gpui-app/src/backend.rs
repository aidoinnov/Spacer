use crate::model::{Progress, Snapshot};
use anyhow::{Context, Result};
use std::{
    io::{BufRead, BufReader},
    path::Path,
    process::{Command, Stdio},
    sync::{Arc, Mutex, mpsc},
};
#[derive(Debug)]
pub enum Event {
    Progress(Progress),
    WatchActive(bool),
    Complete(Arc<Snapshot>),
    Failure(String),
    ImportRoots(Vec<String>),
    ImportCodePage,
    ImportInspection(serde_json::Value),
}
enum SourceMode {
    Scan { watch: bool, include_mounted: bool },
    Open,
    Inspect,
    Documents,
}
pub struct ScanSession {
    process: Arc<crate::document::NativeProcess>,
    pub events: mpsc::Receiver<Event>,
}
impl ScanSession {
    pub fn start_scoped(
        program: &Path,
        root: &Path,
        watch: bool,
        include_mounted: bool,
    ) -> Result<Self> {
        Self::launch(
            program,
            root,
            SourceMode::Scan {
                watch,
                include_mounted,
            },
        )
    }
    pub fn open(program: &Path, path: &Path) -> Result<Self> {
        Self::launch(program, path, SourceMode::Open)
    }
    pub fn documents(program: &Path) -> Result<Self> {
        Self::launch(program, Path::new(""), SourceMode::Documents)
    }
    pub fn inspect(program: &Path, path: &Path) -> Result<Self> {
        Self::launch(program, path, SourceMode::Inspect)
    }
    fn launch(program: &Path, root: &Path, mode: SourceMode) -> Result<Self> {
        let (watch, include_mounted) = match mode {
            SourceMode::Scan {
                watch,
                include_mounted,
            } => (watch, include_mounted),
            _ => (false, false),
        };
        let import = matches!(mode, SourceMode::Open | SourceMode::Inspect);
        let directory = std::env::temp_dir().join(format!(
            "sniffer-gpui-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_nanos()
        ));
        std::fs::create_dir(&directory)?;
        let output = directory.join("snapshot.ssw");
        #[cfg(feature = "qa")]
        let wire = if std::env::args().any(|arg| arg == "--qa-wire-json") {
            "json"
        } else {
            "binary"
        };
        #[cfg(not(feature = "qa"))]
        let wire = "binary";
        let mut command = Command::new(program);
        command
            .arg(if matches!(mode, SourceMode::Documents) {
                "--documents"
            } else if import {
                "--open"
            } else {
                "--scan"
            })
            .arg(root)
            .arg("--output")
            .arg(&output)
            .arg("--parent")
            .arg(std::process::id().to_string())
            .arg("--wire")
            .arg(wire)
            .arg("--watch")
            .arg(if watch { "true" } else { "false" })
            .arg("--volumes")
            .arg(if include_mounted {
                "allVolumes"
            } else {
                "selectedVolume"
            })
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if matches!(mode, SourceMode::Inspect) {
            command.arg("--inspect-only");
        }
        crate::platform::process::configure_child_process(&mut command);
        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                let _ = std::fs::remove_dir_all(&directory);
                return Err(error).with_context(|| {
                    format!("기존 엔진을 실행하지 못했습니다: {}", program.display())
                });
            }
        };
        let mut input = child.stdin.take().context("engine stdin")?;
        let (commands, command_rx) = mpsc::channel::<String>();
        std::thread::spawn(move || {
            use std::io::Write;
            for line in command_rx {
                if writeln!(input, "{line}")
                    .and_then(|_| input.flush())
                    .is_err()
                {
                    break;
                }
            }
        });
        let stdout = child.stdout.take().context("engine stdout")?;
        let stderr = child.stderr.take().context("engine stderr")?;
        let child = Arc::new(Mutex::new(child));
        let shared = child.clone();
        let process = Arc::new(crate::document::NativeProcess {
            child,
            pending: Default::default(),
            commands,
            stopping: Default::default(),
        });
        crate::session_lifecycle::register(process.child.clone(), process.commands.clone(), directory.clone())?;
        let pending = process.pending.clone();
        let process_weak = Arc::downgrade(&process);
        let (tx, events) = mpsc::channel();
        let errors = Arc::new(Mutex::new(String::new()));
        let stderr_errors = errors.clone();
        std::thread::spawn(move || {
            for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                let mut e = stderr_errors.lock().unwrap();
                if e.len() < 8192 {
                    e.push_str(&line);
                    e.push('\n')
                }
            }
        });
        std::thread::spawn(move || {
            let mut completed = false;
            let mut previous = std::sync::Weak::<Snapshot>::new();
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) else {
                    continue;
                };
                match value.get("type").and_then(|v| v.as_str()) {
                    Some("progress") => {
                        if let Ok(p) = serde_json::from_value(value) {
                            let _ = tx.send(Event::Progress(p));
                        }
                    }
                    Some("complete") => match (|| -> Result<Arc<Snapshot>> {
                        let cached = previous.upgrade();
                        let version = cached.as_ref().and_then(|s| s.wire_version.as_deref());
                        Ok(match Snapshot::load_except(&output, version)? {
                            Some(source) => source,
                            None => cached.context("snapshot lease expired")?,
                        })
                    })() {
                        Ok(mut s) => {
                            let version = s
                                .wire_version
                                .clone()
                                .or_else(|| value["version"].as_str().map(str::to_owned));
                            if s.document.is_none()
                                && let (Some(process), Some(version)) =
                                    (process_weak.upgrade(), version)
                            {
                                Arc::get_mut(&mut s).unwrap().document =
                                    Some(crate::document::NativeDocument { process, version });
                            }
                            completed = true;
                            previous = Arc::downgrade(&s);
                            let _ = tx.send(Event::Complete(s));
                        }
                        Err(e) => {
                            let _ = tx.send(Event::Failure(e.to_string()));
                        }
                    },
                    Some("documentReady") => {
                        completed = true;
                    }
                    Some("watchState") => {
                        let _ = tx.send(Event::WatchActive(
                            value["active"].as_bool().unwrap_or(false),
                        ));
                    }
                    Some("importInspection") => {
                        completed = true;
                        let _ = tx.send(Event::ImportInspection(value["roots"].clone()));
                    }
                    Some("importRoots") => {
                        let roots =
                            serde_json::from_value(value["roots"].clone()).unwrap_or_default();
                        let _ = tx.send(Event::ImportRoots(roots));
                    }
                    Some("importCodePage") => {
                        let _ = tx.send(Event::ImportCodePage);
                    }
                    Some("failure") => {
                        let _ = tx.send(Event::Failure(
                            value["message"].as_str().unwrap_or("분석 실패").to_string(),
                        ));
                    }
                    Some("documentData" | "documentEnd" | "documentError") => {
                        crate::document::route(&pending, &value)
                    }
                    _ => {}
                }
            }
            crate::document::disconnected(&pending);
            let status = loop {
                let status = shared.lock().unwrap().try_wait();
                if !matches!(status, Ok(None)) {
                    break status;
                }
                std::thread::sleep(std::time::Duration::from_millis(20));
            };
            if !completed {
                let _ = tx.send(Event::Failure(format!(
                    "분석 엔진이 완료 결과 없이 종료됐습니다. {status:?} {}",
                    errors.lock().unwrap()
                )));
            }
            if std::fs::remove_dir_all(&directory).is_ok() || !directory.exists() {
                crate::session_lifecycle::unregister(&directory);
            }
        });
        Ok(Self { process, events })
    }
    #[cfg(feature = "qa")]
    pub fn process_id(&self) -> u32 {
        self.process.child.lock().unwrap().id()
    }
    pub fn send(&self, line: &str) {
        self.process.send(line);
    }
    pub fn is_alive(&self) -> bool {
        self.process
            .child
            .lock()
            .unwrap()
            .try_wait()
            .is_ok_and(|value| value.is_none())
    }
    pub fn process_handle(&self) -> Arc<crate::document::NativeProcess> {
        self.process.clone()
    }
    pub fn cancel(&self) {
        self.send("cancel");
    }
}
impl Drop for ScanSession {
    fn drop(&mut self) {
        self.send("watch false");
        self.cancel();
    }
}
