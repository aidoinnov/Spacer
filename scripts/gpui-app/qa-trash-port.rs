//! Exercises only a file created here, using the same pinned trash port as the UI.
//! Build with rustc --extern trash=... -L dependency=...; never empties Trash.
use std::{fs, time::{SystemTime, UNIX_EPOCH}};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let nonce = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let name = format!("sniffer-owned-trash-{}-{nonce}.txt", std::process::id());
    let root = std::env::temp_dir().join(format!("sniffer-trash-test-{nonce}"));
    fs::create_dir(&root)?;
    let source = root.join(&name);
    let content = b"Owned Space Sniffer trash and restore verification";
    fs::write(&source, content)?;
    trash::delete(&source)?;
    assert!(!source.exists(), "File was not moved to Trash");
    #[cfg(target_os = "macos")]
    {
        let trashed = std::path::PathBuf::from(std::env::var_os("HOME").ok_or("HOME missing")?).join(".Trash").join(&name);
        assert_eq!(fs::read(&trashed)?, content);
        fs::rename(&trashed, &source)?;
    }
    #[cfg(target_os = "windows")]
    {
        let owned = trash::os_limited::list()?.into_iter().filter(|item| item.original_path() == source).collect::<Vec<_>>();
        assert_eq!(owned.len(), 1, "Owned recycle item missing or ambiguous");
        trash::os_limited::restore_all(owned)?;
    }
    assert_eq!(fs::read(&source)?, content);
    fs::remove_file(&source)?;
    fs::remove_dir(&root)?;
    println!("{{\"passed\":true,\"movedToTrash\":true,\"restoredContentUnchanged\":true,\"ownedFixtureRemoved\":true}}");
    Ok(())
}
