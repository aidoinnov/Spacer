use std::{
    io,
    os::unix::{
        fs::{MetadataExt, PermissionsExt},
        io::{AsRawFd, FromRawFd},
        net::{UnixListener, UnixStream},
    },
    path::PathBuf,
    time::Duration,
};
pub struct Listener {
    listener: UnixListener,
    socket: PathBuf,
    descriptor: PathBuf,
}
impl Listener {
    pub fn bind(nonce: &str, token: &str, bundle_id: &str) -> anyhow::Result<Self> {
        let uid = unsafe { libc::getuid() };
        let directory = PathBuf::from(format!("/tmp/mac-space-sniffer-{uid}"));
        match std::fs::create_dir(&directory) {
            Ok(()) => std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700))?,
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {}
            Err(e) => return Err(e.into()),
        }
        let metadata = std::fs::symlink_metadata(&directory)?;
        anyhow::ensure!(
            metadata.is_dir() && metadata.uid() == uid && metadata.mode() & 0o077 == 0,
            "Control directory must be owned by this user with mode 0700"
        );
        let stem = format!("{}-{nonce}", std::process::id());
        let socket = directory.join(format!("{stem}.sock"));
        let descriptor = directory.join(format!("{stem}.json"));
        let listener = UnixListener::bind(&socket)?;
        std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600))?;
        listener.set_nonblocking(true)?;
        let data = serde_json::json!({"pid":std::process::id(),"bundle_id":bundle_id,"socket":socket,"token":token,"version":1,"ui":"gpui"});
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut output = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&descriptor)?;
        output.write_all(serde_json::to_string(&data)?.as_bytes())?;
        Ok(Self {
            listener,
            socket,
            descriptor,
        })
    }
    pub fn cleanup_paths(&self) -> Vec<PathBuf> {
        vec![self.descriptor.clone(), self.socket.clone()]
    }
    pub fn accept(&mut self) -> io::Result<Option<UnixStream>> {
        // No peer pathname is needed. Some unnamed local clients have no sockaddr
        // payload; accept the descriptor and authenticate its UID directly.
        let fd = unsafe {
            libc::accept(
                self.listener.as_raw_fd(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };
        if fd < 0 {
            let error = io::Error::last_os_error();
            return if error.kind() == io::ErrorKind::WouldBlock {
                Ok(None)
            } else {
                Err(error)
            };
        }
        let stream = unsafe { UnixStream::from_raw_fd(fd) };
        let mut uid = 0;
        let mut gid = 0;
        if unsafe { libc::getpeereid(fd, &mut uid, &mut gid) } != 0
            || uid != unsafe { libc::getuid() }
        {
            return Ok(None);
        }
        let enabled: libc::c_int = 1;
        unsafe {
            libc::setsockopt(
                fd,
                libc::SOL_SOCKET,
                libc::SO_NOSIGPIPE,
                (&enabled as *const libc::c_int).cast(),
                std::mem::size_of_val(&enabled) as libc::socklen_t,
            );
        }
        if stream
            .set_nonblocking(false)
            .and_then(|_| stream.set_read_timeout(Some(Duration::from_secs(15))))
            .and_then(|_| stream.set_write_timeout(Some(Duration::from_secs(15))))
            .is_err()
        {
            return Ok(None);
        }
        Ok(Some(stream))
    }
}
impl Drop for Listener {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.descriptor);
        let _ = std::fs::remove_file(&self.socket);
    }
}
#[cfg(test)]
pub fn test_connect(descriptor: &serde_json::Value) -> io::Result<UnixStream> {
    UnixStream::connect(descriptor["socket"].as_str().unwrap())
}
