//! Process presentation and companion discovery shared by GUI and console hosts.
use std::{
    path::{Path, PathBuf},
    process::Command,
};

pub fn configure_child_process(command: &mut Command) {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x0800_0000); // CREATE_NO_WINDOW for native companions.
    }
    #[cfg(not(target_os = "windows"))]
    let _ = command;
}

pub fn backend() -> PathBuf {
    if let Some(path) = std::env::var_os("SNIFFER_SCAN_BACKEND") {
        return path.into();
    }
    companion(if cfg!(target_os = "windows") {
        "ExplorerBackend.exe"
    } else {
        "MacScanBridge"
    })
}

pub fn cli() -> PathBuf {
    companion(if cfg!(target_os = "windows") {
        "SpacerCLI.exe"
    } else {
        "SpacerCLI"
    })
}

/// Keep a private stdin lease open until the console host exits. If the GUI
/// forwarder is terminated, EOF cancels the host and its owned native process.
pub fn run_cli(args: &[std::ffi::OsString]) -> std::io::Result<i32> {
    use std::process::Stdio;
    let mut command = Command::new(cli());
    command
        .args(args)
        .arg("--parent-stdio")
        .stdin(Stdio::piped());
    configure_child_process(&mut command);
    let mut child = command.spawn()?;
    let lease = child.stdin.take(); // Child::wait must not close this lease early.
    let status = child.wait()?;
    drop(lease);
    Ok(status.code().unwrap_or(1))
}

fn companion(name: &str) -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
        .unwrap_or_default()
        .join(name)
}
