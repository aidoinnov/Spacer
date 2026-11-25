//! Owned native-process shutdown and scratch-file cleanup for both hosts.
use anyhow::{Context, Result, bail};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    process::Child,
    sync::{Arc, Mutex, OnceLock, mpsc},
    time::{Duration, Instant},
};

#[derive(Clone)]
struct Runtime {
    child: Arc<Mutex<Child>>,
    commands: mpsc::Sender<String>,
    directory: PathBuf,
}
#[derive(Default)]
struct Registry {
    closing: bool,
    runtimes: HashMap<PathBuf, Runtime>,
}
fn registry() -> &'static Mutex<Registry> {
    static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();
    REGISTRY.get_or_init(Default::default)
}

pub fn register(
    child: Arc<Mutex<Child>>,
    commands: mpsc::Sender<String>,
    directory: PathBuf,
) -> Result<()> {
    let runtime = Runtime {
        child,
        commands,
        directory,
    };
    let mut registry = registry().lock().unwrap();
    if registry.closing {
        drop(registry);
        return runtime.finish(Instant::now());
    }
    registry.runtimes.insert(runtime.directory.clone(), runtime);
    Ok(())
}

pub fn unregister(directory: &Path) {
    registry().lock().unwrap().runtimes.remove(directory);
}

impl Runtime {
    fn request_stop(&self) {
        let _ = self.commands.send("quit".into());
        let _ = self.commands.send("cancel".into());
    }
    fn finish(&self, deadline: Instant) -> Result<()> {
        self.request_stop();
        loop {
            let mut child = self.child.lock().unwrap();
            if child.try_wait()?.is_some() {
                break;
            }
            if Instant::now() >= deadline {
                child.kill().context("Terminate owned native process")?;
                child.wait().context("Reap owned native process")?;
                break;
            }
            drop(child);
            std::thread::sleep(Duration::from_millis(10));
        }
        // A Windows reader can briefly retain a handle after native exit.
        let cleanup_deadline = Instant::now() + Duration::from_millis(100);
        loop {
            match std::fs::remove_dir_all(&self.directory) {
                Ok(()) => return Ok(()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
                Err(_) if Instant::now() < cleanup_deadline => {
                    std::thread::sleep(Duration::from_millis(10))
                }
                Err(e) => return Err(e).context("Remove owned native scratch directory"),
            }
        }
    }
}

/// Quit all owned engines together before waiting; the grace budget is shared.
/// Called synchronously at terminal/app exit, before the host can kill readers.
pub fn finish_all() -> Result<()> {
    let runtimes = {
        let mut registry = registry().lock().unwrap();
        registry.closing = true;
        std::mem::take(&mut registry.runtimes)
    };
    for runtime in runtimes.values() {
        runtime.request_stop();
    }
    let deadline = Instant::now() + Duration::from_secs(1);
    let errors: Vec<_> = runtimes
        .values()
        .filter_map(|runtime| runtime.finish(deadline).err())
        .collect();
    if !errors.is_empty() {
        bail!("Native shutdown cleanup failed: {errors:?}");
    }
    Ok(())
}
