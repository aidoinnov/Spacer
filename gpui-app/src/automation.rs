//! Bounded authenticated transport and UI handoff. No filesystem actions are exposed here.
use serde_json::{Value, json};
use std::{
    io::{BufRead, BufReader, Read, Write},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
        mpsc,
    },
    time::Duration,
};
pub const BUNDLE_ID: &str = match option_env!("SPACE_SNIFFER_BUNDLE_ID") {
    Some(value) => value,
    None => env!("SPACER_BUNDLE_ID"),
};
pub struct Request {
    pub value: Value,
    pub reply: mpsc::SyncSender<Value>,
}
#[derive(Clone)]
pub struct Shutdown {
    stop: Arc<AtomicBool>,
    paths: Vec<std::path::PathBuf>,
}
impl Shutdown {
    pub fn stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
        for path in &self.paths {
            let _ = std::fs::remove_file(path);
        }
    }
}
pub struct Server {
    requests: mpsc::Receiver<Request>,
    shutdown: Shutdown,
}
impl Server {
    pub fn start() -> anyhow::Result<Self> {
        let mut random = [0u8; 32];
        getrandom::fill(&mut random).map_err(|e| anyhow::anyhow!("control entropy: {e}"))?;
        let token: String = random.iter().map(|b| format!("{b:02x}")).collect();
        let nonce = &token[..8];
        let mut listener = crate::platform::control::Listener::bind(nonce, &token, BUNDLE_ID)?;
        let paths = listener.cleanup_paths();
        let (tx, requests) = mpsc::sync_channel::<Request>(8);
        let stop = Arc::new(AtomicBool::new(false));
        let stopped = stop.clone();
        std::thread::spawn(move || {
            let active = Arc::new(AtomicUsize::new(0));
            while !stopped.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok(Some(stream)) if active.load(Ordering::Relaxed) < 4 => {
                        active.fetch_add(1, Ordering::Relaxed);
                        let active = active.clone();
                        let token = token.clone();
                        let tx = tx.clone();
                        std::thread::spawn(move || {
                            let mut stream = BufReader::new(stream);
                            let result = (|| -> anyhow::Result<Value> {
                                let mut line = String::new();
                                std::io::Read::by_ref(&mut stream)
                                    .take(1_048_577)
                                    .read_line(&mut line)?;
                                anyhow::ensure!(
                                    line.len() <= 1_048_576 && line.ends_with('\n'),
                                    "invalid_request"
                                );
                                let value: Value = serde_json::from_str(&line)?;
                                let supplied = value["token"].as_str().unwrap_or("");
                                anyhow::ensure!(
                                    constant_time_equal(token.as_bytes(), supplied.as_bytes()),
                                    "unauthorized"
                                );
                                let (reply, rx) = mpsc::sync_channel(1);
                                tx.try_send(Request { value, reply })
                                    .map_err(|_| anyhow::anyhow!("busy"))?;
                                Ok(rx.recv_timeout(Duration::from_secs(25))?)
                            })();
                            let response=result.unwrap_or_else(|error|json!({"id":null,"error":{"code":"control_error","message":error.to_string()}}));
                            if let Ok(mut bytes) = serde_json::to_vec(&response)
                                && bytes.len() <= 16_777_216
                            {
                                bytes.push(b'\n');
                                let _ = stream.get_mut().write_all(&bytes);
                            }
                            active.fetch_sub(1, Ordering::Relaxed);
                        });
                    }
                    Ok(_) => {}
                    Err(error)
                        if matches!(
                            error.kind(),
                            std::io::ErrorKind::Interrupted | std::io::ErrorKind::ConnectionAborted
                        ) => {}
                    Err(error) => {
                        eprintln!("Local control accept failed: {error}");
                        break;
                    }
                }
                std::thread::sleep(Duration::from_millis(20));
            }
        });
        Ok(Self {
            requests,
            shutdown: Shutdown { stop, paths },
        })
    }
    pub fn try_recv(&self) -> Result<Request, mpsc::TryRecvError> {
        self.requests.try_recv()
    }
    pub fn shutdown_handle(&self) -> Shutdown {
        self.shutdown.clone()
    }
}
impl Drop for Server {
    fn drop(&mut self) {
        self.shutdown.stop();
    }
}
fn constant_time_equal(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |diff, (a, b)| diff | (a ^ b)) == 0
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn local_transport_survives_empty_probe_authenticates_and_cleans_registry() {
        let server = Server::start().unwrap();
        let descriptor = server
            .shutdown
            .paths
            .iter()
            .find(|p| p.extension().is_some_and(|e| e == "json"))
            .unwrap();
        let data: Value = serde_json::from_slice(&std::fs::read(descriptor).unwrap()).unwrap();
        drop(crate::platform::control::test_connect(&data).unwrap());
        std::thread::sleep(Duration::from_millis(80));
        let client = std::thread::spawn(move || {
            let mut stream = crate::platform::control::test_connect(&data).unwrap();
            writeln!(
                stream,
                "{}",
                json!({"id":7,"token":data["token"],"command":"app_status","arguments":{}})
            )
            .unwrap();
            let mut line = String::new();
            BufReader::new(stream).read_line(&mut line).unwrap();
            let reply: Value = serde_json::from_str(&line).unwrap();
            assert_eq!(reply["result"]["alive"], true);
        });
        let started = std::time::Instant::now();
        loop {
            if let Ok(request) = server.try_recv() {
                request
                    .reply
                    .send(json!({"id":7,"result":{"alive":true}}))
                    .unwrap();
                break;
            }
            assert!(started.elapsed() < Duration::from_secs(3));
            std::thread::sleep(Duration::from_millis(10));
        }
        client.join().unwrap();
        let paths = server.shutdown.paths.clone();
        drop(server);
        for path in paths {
            assert!(!path.exists());
        }
    }
}
