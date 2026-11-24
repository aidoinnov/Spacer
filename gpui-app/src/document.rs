//! Native document RPC. Immutable source tokens prevent stale filter/export results.
//! The stdout reader delivers bounded chunks; destination files never live on the UI lane.
use anyhow::{Context, Result, bail};
use base64::Engine;
use serde_json::Value;
use std::{
    collections::HashMap,
    io::Write,
    process::Child,
    sync::{Arc, Mutex, mpsc},
    time::Duration,
};

type Pending = Arc<Mutex<HashMap<String, mpsc::SyncSender<Reply>>>>;
pub enum Reply {
    Data(Vec<u8>),
    End(u64),
    Error(String),
}
pub struct NativeProcess {
    pub child: Arc<Mutex<Child>>,
    pub pending: Pending,
    pub commands: mpsc::Sender<String>,
    pub stopping: std::sync::atomic::AtomicBool,
}
impl std::fmt::Debug for NativeProcess {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("NativeProcess")
    }
}
impl NativeProcess {
    pub fn send(&self, line: &str) {
        let _ = self.commands.send(line.to_string());
    }
    pub fn shutdown(&self) {
        if self
            .stopping
            .swap(true, std::sync::atomic::Ordering::Relaxed)
        {
            return;
        }
        self.send("quit");
        self.send("cancel");
        let child = self.child.clone();
        std::thread::spawn(move || {
            let start = std::time::Instant::now();
            loop {
                if child
                    .lock()
                    .unwrap()
                    .try_wait()
                    .map_or(true, |s| s.is_some())
                {
                    break;
                }
                if start.elapsed() > Duration::from_secs(5) {
                    let _ = child.lock().unwrap().kill();
                    break;
                }
                std::thread::sleep(Duration::from_millis(25));
            }
        });
    }
}
impl Drop for NativeProcess {
    fn drop(&mut self) {
        self.shutdown();
    }
}

#[derive(Clone, Debug)]
pub struct NativeDocument {
    pub process: Arc<NativeProcess>,
    pub version: String,
}
impl NativeDocument {
    pub fn request(&self, mut command: Value, output: &mut impl Write) -> Result<()> {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let request = NEXT
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed)
            .to_string();
        command["request"] = request.clone().into();
        command["version"] = self.version.clone().into();
        let (tx, rx) = mpsc::sync_channel(4);
        self.process
            .pending
            .lock()
            .unwrap()
            .insert(request.clone(), tx);
        self.process.send(&serde_json::to_string(&command)?);
        let result = (|| {
            let mut count = 0u64;
            loop {
                match rx
                    .recv_timeout(Duration::from_secs(120))
                    .context("문서 엔진 응답 시간 초과 또는 종료")?
                {
                    Reply::Data(bytes) => {
                        output.write_all(&bytes)?;
                        count += bytes.len() as u64;
                    }
                    Reply::End(expected) => {
                        if expected != count {
                            bail!("문서 전송 길이가 일치하지 않습니다.");
                        }
                        return Ok(());
                    }
                    Reply::Error(message) => bail!(message),
                }
            }
        })();
        self.process.pending.lock().unwrap().remove(&request);
        result
    }
    pub fn weights(
        &self,
        text: &str,
        logical: bool,
        hidden: bool,
        tags: &HashMap<String, u8>,
        count: usize,
    ) -> Result<Vec<u64>> {
        let mut bytes = Vec::new();
        self.request(serde_json::json!({"operation":"weights", "filter":text, "logical":logical, "hidden":hidden, "tags":tags}), &mut bytes)?;
        if bytes.len() / 8 != count || bytes.len() % 8 != 0 {
            bail!("필터 결과 노드 수가 일치하지 않습니다.");
        }
        Ok(bytes
            .chunks_exact(8)
            .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
            .collect())
    }
}
pub fn route(pending: &Pending, value: &Value) {
    let Some(id) = value["request"].as_str() else {
        return;
    };
    let sender = pending.lock().unwrap().get(id).cloned();
    if let Some(sender) = sender {
        let reply = match value["type"].as_str() {
            Some("documentData") => match base64::engine::general_purpose::STANDARD
                .decode(value["data"].as_str().unwrap_or(""))
            {
                Ok(bytes) if bytes.len() <= 65_536 => Reply::Data(bytes),
                _ => Reply::Error("잘못된 문서 전송 데이터입니다.".into()),
            },
            Some("documentEnd") => Reply::End(value["bytes"].as_u64().unwrap_or(u64::MAX)),
            _ => Reply::Error(value["message"].as_str().unwrap_or("문서 작업 실패").into()),
        };
        let _ = sender.send(reply);
    }
}
pub fn disconnected(pending: &Pending) {
    let senders: Vec<_> = pending.lock().unwrap().drain().map(|(_, s)| s).collect();
    for sender in senders {
        let _ = sender.send(Reply::Error("문서 엔진이 종료됐습니다.".into()));
    }
}

/// Publish only a complete, synchronized native stream. Dropping staging preserves old output.
pub fn save_atomic(
    document: &NativeDocument,
    command: Value,
    path: &std::path::Path,
) -> Result<()> {
    atomic_write(path, |output| document.request(command, output))
}
pub fn save_new_atomic(
    document: &NativeDocument,
    command: Value,
    path: &std::path::Path,
) -> Result<()> {
    atomic_write_mode(path, false, |output| document.request(command, output))
}
fn atomic_write(
    path: &std::path::Path,
    write: impl FnOnce(&mut std::fs::File) -> Result<()>,
) -> Result<()> {
    atomic_write_mode(path, true, write)
}
fn atomic_write_mode(
    path: &std::path::Path,
    replace: bool,
    write: impl FnOnce(&mut std::fs::File) -> Result<()>,
) -> Result<()> {
    let parent = path.parent().context("저장할 폴더가 없습니다.")?;
    let mut staged = tempfile::NamedTempFile::new_in(parent)?;
    write(staged.as_file_mut())?;
    staged.as_file().sync_all()?;
    if replace {
        staged.persist(path).map_err(|e| e.error)?;
    } else {
        staged.persist_noclobber(path).map_err(|e| e.error)?;
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn new_output_never_overwrites_a_file_created_during_streaming() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("new.sns");
        let result = atomic_write_mode(&path, false, |out| {
            out.write_all(b"export")?;
            std::fs::write(&path, b"racing writer")?;
            Ok(())
        });
        assert!(result.is_err());
        assert_eq!(std::fs::read(&path).unwrap(), b"racing writer");
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
    }
    #[test]
    fn failed_stream_preserves_existing_file_and_removes_staging() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("saved.sns");
        std::fs::write(&path, b"previous").unwrap();
        assert!(
            atomic_write(&path, |f| {
                f.write_all(b"truncated")?;
                bail!("engine failed")
            })
            .is_err()
        );
        assert_eq!(std::fs::read(&path).unwrap(), b"previous");
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
        atomic_write(&path, |f| {
            f.write_all(b"complete")?;
            Ok(())
        })
        .unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"complete");
    }
}
