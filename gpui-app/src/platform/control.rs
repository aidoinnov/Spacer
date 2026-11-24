//! Private local transport is an OS port; request routing stays common.
#[cfg(target_os = "macos")]
#[path = "macos/control.rs"]
mod transport;
#[cfg(target_os = "windows")]
#[path = "windows/control.rs"]
mod transport;
pub use transport::Listener;
#[cfg(test)]
pub use transport::test_connect;
