use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use std::{path::Path, sync::mpsc, time::Instant};
pub struct ChangeMonitor {
    _watcher: RecommendedWatcher,
    pub events: mpsc::Receiver<Instant>,
}
impl ChangeMonitor {
    pub fn start(root: &Path) -> anyhow::Result<Self> {
        let (tx, events) = mpsc::channel();
        let cache = std::env::temp_dir();
        let mut watcher =
            notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
                let relevant = match event {
                    Ok(e) => !e.paths.iter().all(|p| {
                        p.starts_with(&cache)
                            && p.components().any(|c| {
                                c.as_os_str().to_string_lossy().starts_with("sniffer-gpui-")
                            })
                    }),
                    Err(_) => true,
                };
                if relevant {
                    let _ = tx.send(Instant::now());
                }
            })?;
        watcher.watch(root, RecursiveMode::Recursive)?;
        Ok(Self {
            _watcher: watcher,
            events,
        })
    }
}
