//! Native spelling shared by GUI scope checks and headless scans.
use std::path::PathBuf;

#[cfg(target_os = "macos")]
pub fn scan_path(path: &std::path::Path) -> PathBuf {
    let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    for (native, display) in [
        ("/private/tmp", "/tmp"),
        ("/private/var", "/var"),
        ("/private/etc", "/etc"),
    ] {
        if let Ok(suffix) = canonical.strip_prefix(native) {
            return std::path::Path::new(display).join(suffix);
        }
    }
    canonical
}

#[cfg(target_os = "windows")]
pub fn scan_path(path: &std::path::Path) -> PathBuf {
    // A missing leaf still needs the existing parent's spelling (Temp/TEMP,
    // drive case and short names) before scope checks and error classification.
    let p = path
        .ancestors()
        .find_map(|ancestor| {
            std::fs::canonicalize(ancestor).ok().map(|parent| {
                let suffix = path.strip_prefix(ancestor).unwrap();
                if suffix.as_os_str().is_empty() {
                    parent
                } else {
                    parent.join(suffix)
                }
            })
        })
        .unwrap_or_else(|| path.to_path_buf());
    let text = p.to_string_lossy();
    if let Some(suffix) = text.strip_prefix("\\\\?\\UNC\\") {
        return format!("\\\\{suffix}").into();
    }
    if let Some(suffix) = text.strip_prefix("\\\\?\\") {
        return suffix.into();
    }
    p
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn scan_path(path: &std::path::Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}
