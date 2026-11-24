//! One active operation and one replaceable pending operation per owner.
//! Superseded pending work never enters the expensive native document lane.
use std::sync::{Arc, Condvar, Mutex, mpsc};
type Job = Box<dyn FnOnce() + Send>;
#[derive(Default)]
struct State {
    pending: Option<Job>,
    stopped: bool,
    stats: Statistics,
}
#[derive(Clone, Copy, Default, serde::Serialize)]
pub struct Statistics {
    pub submitted: u64,
    pub started: u64,
    pub completed: u64,
    pub coalesced: u64,
    pub active: usize,
    pub pending: usize,
    pub peak_active: usize,
}
pub struct LatestWork {
    state: Arc<(Mutex<State>, Condvar)>,
}
impl LatestWork {
    pub fn new() -> Self {
        let state = Arc::new((Mutex::new(State::default()), Condvar::new()));
        let worker = state.clone();
        std::thread::spawn(move || {
            loop {
                let job = {
                    let (lock, wake) = &*worker;
                    let mut state = lock.lock().unwrap();
                    while !state.stopped && state.pending.is_none() {
                        state = wake.wait(state).unwrap();
                    }
                    if state.stopped {
                        return;
                    }
                    state.stats.started += 1;
                    state.stats.active = 1;
                    state.stats.peak_active = 1;
                    state.pending.take().unwrap()
                };
                job();
                let mut state = worker.0.lock().unwrap();
                state.stats.active = 0;
                state.stats.completed += 1;
            }
        });
        Self { state }
    }
    pub fn statistics(&self) -> Statistics {
        let state = self.state.0.lock().unwrap();
        let mut stats = state.stats;
        stats.pending = usize::from(state.pending.is_some());
        stats
    }
    pub fn submit<T: Send + 'static>(
        &self,
        work: impl FnOnce() -> T + Send + 'static,
    ) -> mpsc::Receiver<T> {
        let (tx, rx) = mpsc::channel();
        let (lock, wake) = &*self.state;
        let replaced = {
            let mut state = lock.lock().unwrap();
            state.stats.submitted += 1;
            let previous = state.pending.replace(Box::new(move || {
                let _ = tx.send(work());
            }));
            if previous.is_some() {
                state.stats.coalesced += 1;
            }
            previous
        };
        drop(replaced);
        wake.notify_one();
        rx
    }
}
impl Drop for LatestWork {
    fn drop(&mut self) {
        let (lock, wake) = &*self.state;
        let mut state = lock.lock().unwrap();
        state.stopped = true;
        state.pending = None;
        wake.notify_one();
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        sync::atomic::{AtomicUsize, Ordering},
        time::Duration,
    };
    #[test]
    fn rapid_replacement_executes_only_active_and_latest() {
        let worker = LatestWork::new();
        let (started_tx, started_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let active = worker.submit(move || {
            started_tx.send(()).unwrap();
            release_rx.recv().unwrap();
            0
        });
        started_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        let count = Arc::new(AtomicUsize::new(0));
        let mut latest = None;
        for i in 1..=1000 {
            let count = count.clone();
            latest = Some(worker.submit(move || {
                count.fetch_add(1, Ordering::SeqCst);
                i
            }));
        }
        release_tx.send(()).unwrap();
        assert_eq!(active.recv().unwrap(), 0);
        assert_eq!(
            latest
                .unwrap()
                .recv_timeout(Duration::from_secs(2))
                .unwrap(),
            1000
        );
        assert_eq!(count.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn dropping_owner_discards_pending_without_waiting_for_active() {
        let worker = LatestWork::new();
        let (tx, rx) = mpsc::channel();
        let (started_tx, started_rx) = mpsc::channel();
        let active = worker.submit(move || {
            started_tx.send(()).unwrap();
            rx.recv().unwrap();
        });
        started_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        let pending = worker.submit(|| panic!("pending work must not run"));
        drop(worker);
        assert!(pending.recv_timeout(Duration::from_secs(2)).is_err());
        tx.send(()).unwrap();
        active.recv().unwrap();
    }
}
