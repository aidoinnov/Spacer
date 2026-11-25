//! The preview host is replaceable and owned by a kill-on-close Windows job.
//! No shell preview DLL is loaded into GPUI, and the UI never waits on a handler.
use anyhow::{Context, Result};
use serde::Deserialize;
use std::{
    io::{BufRead, BufReader, Read},
    os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
    path::Path,
    process::{Child, Command, Stdio},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};
use windows::{
    Win32::{
        Foundation::{HANDLE, HWND, LPARAM, WPARAM},
        System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
            SetInformationJobObject,
        },
        UI::WindowsAndMessaging::{GetWindowThreadProcessId, PostMessageW, WM_CLOSE},
    },
    core::PCWSTR,
};

#[derive(Clone, Debug, Default, Deserialize)]
pub struct Observation {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    pub renderer: String,
    #[serde(default)]
    pub visible: bool,
    #[serde(default)]
    pub width: u32,
    #[serde(default)]
    pub height: u32,
    #[serde(default)]
    hwnd: usize,
}
impl Observation {
    fn valid_ready(&self) -> bool {
        self.kind == "ready"
            && self.visible
            && self.hwnd != 0
            && self.width > 0
            && self.height > 0
            && matches!(
                self.renderer.as_str(),
                "text" | "image" | "shell" | "metadata"
            )
    }
}
#[derive(Default)]
struct State {
    current: Option<Preview>,
    message: Option<String>,
}
struct Preview {
    job: Option<OwnedHandle>,
    child: Arc<Mutex<Child>>,
    observation: Arc<Mutex<Observation>>,
    finished: Arc<AtomicBool>,
    window: Arc<AtomicUsize>,
}
fn state() -> &'static Mutex<State> {
    static STATE: OnceLock<Mutex<State>> = OnceLock::new();
    STATE.get_or_init(Default::default)
}
fn create_job() -> Result<OwnedHandle> {
    // A kernel-owned job closes even if the application exits without Rust Drop.
    unsafe {
        let raw = CreateJobObjectW(None, PCWSTR::null())?;
        let owner = OwnedHandle::from_raw_handle(raw.0);
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(
            raw,
            JobObjectExtendedLimitInformation,
            &limits as *const _ as *const _,
            std::mem::size_of_val(&limits) as u32,
        )?;
        Ok(owner)
    }
}
pub fn show(path: &Path) -> Result<()> {
    let program = std::env::current_exe()?
        .parent()
        .context("앱 경로가 없습니다.")?
        .join("WindowsPreviewHost.exe");
    let job = create_job()?;
    let mut command = Command::new(program);
    command
        .arg(path)
        .arg(std::process::id().to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    if std::env::args_os().any(|arg| arg == "--qa-document-only" || arg == "--qa-preview-only") {
        command.arg("quiet");
    }
    crate::platform::process::configure_child_process(&mut command);
    let mut child = command
        .spawn()
        .context("Windows 미리보기 도우미를 실행하지 못했습니다.")?;
    if let Err(error) = unsafe {
        AssignProcessToJobObject(HANDLE(job.as_raw_handle()), HANDLE(child.as_raw_handle()))
    } {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error.into());
    }
    let output = child
        .stdout
        .take()
        .context("미리보기 응답 채널이 없습니다.")?;
    let child = Arc::new(Mutex::new(child));
    let observation = Arc::new(Mutex::new(Observation::default()));
    let finished = Arc::new(AtomicBool::new(false));
    let window = Arc::new(AtomicUsize::new(0));
    let preview = Preview {
        job: Some(job),
        child: child.clone(),
        observation: observation.clone(),
        finished: finished.clone(),
        window: window.clone(),
    };
    // Replacing a preview closes its owned window asynchronously.
    let old = {
        let mut state = state().lock().unwrap();
        state.message = None;
        state.current.replace(preview)
    };
    drop(old);
    let read_finished = finished.clone();
    std::thread::spawn(move || {
        let mut reader = BufReader::new(output);
        loop {
            let mut line = String::new();
            if !matches!(
                Read::by_ref(&mut reader).take(4097).read_line(&mut line),
                Ok(1..)
            ) || line.len() > 4096
                || !line.ends_with('\n')
            {
                break;
            }
            if let Ok(value) = serde_json::from_str::<Observation>(&line)
                && value.valid_ready()
            {
                window.store(value.hwnd, Ordering::Release);
                *observation.lock().unwrap() = value;
            }
        }
        read_finished.store(true, Ordering::Release);
        observation.lock().unwrap().visible = false;
    });
    std::thread::spawn(move || {
        let start = Instant::now();
        loop {
            let ready = {
                let state = state().lock().unwrap();
                state.current.as_ref().is_some_and(|p| {
                    Arc::ptr_eq(&p.child, &child) && p.observation.lock().unwrap().kind == "ready"
                })
            };
            if ready {
                return;
            }
            let done = finished.load(Ordering::Acquire);
            if done || start.elapsed() > Duration::from_secs(10) {
                let mut state = state().lock().unwrap();
                if state
                    .current
                    .as_ref()
                    .is_some_and(|p| Arc::ptr_eq(&p.child, &child))
                {
                    state.message = Some(
                        if done {
                            "미리보기 도우미가 준비 전에 종료됐습니다."
                        } else {
                            "미리보기 준비 시간이 초과됐습니다."
                        }
                        .into(),
                    );
                    let old = state.current.take();
                    drop(state);
                    drop(old);
                }
                return;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    });
    Ok(())
}
#[cfg(feature = "qa")]
pub fn observation() -> Option<Observation> {
    let state = state().lock().unwrap();
    state
        .current
        .as_ref()
        .map(|p| p.observation.lock().unwrap().clone())
}
pub fn message() -> Option<String> {
    state().lock().unwrap().message.take()
}
impl Drop for Preview {
    fn drop(&mut self) {
        let job = self.job.take();
        let child = self.child.clone();
        let window = self.window.load(Ordering::Acquire);
        let finished = self.finished.clone();
        std::thread::spawn(move || {
            let mut owner = 0;
            // Verify ownership before posting to a handle which may have been recycled.
            if !finished.load(Ordering::Acquire) && window != 0 {
                unsafe {
                    let hwnd = HWND(window as *mut _);
                    GetWindowThreadProcessId(hwnd, Some(&mut owner));
                    if owner == child.lock().unwrap().id() {
                        let _ = PostMessageW(Some(hwnd), WM_CLOSE, WPARAM(0), LPARAM(0));
                    }
                }
            }
            let start = Instant::now();
            while start.elapsed() < Duration::from_secs(1) {
                if child
                    .lock()
                    .unwrap()
                    .try_wait()
                    .map_or(true, |exit| exit.is_some())
                {
                    break;
                }
                std::thread::sleep(Duration::from_millis(25));
            }
            drop(job); // force cleanup only for this preview if it did not close normally
        });
    }
}
