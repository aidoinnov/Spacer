//! Per-user ACL named pipes; never a public TCP listener.
use std::{
    io::{self, Read, Write},
    os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
    path::PathBuf,
    time::{Duration, Instant},
};
use windows::{
    Win32::{
        Foundation::{
            ERROR_BROKEN_PIPE, ERROR_NO_DATA, ERROR_PIPE_CONNECTED, ERROR_PIPE_LISTENING, HANDLE,
            HLOCAL, LocalFree,
        },
        Security::{
            Authorization::{
                ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
            },
            GetTokenInformation, PSECURITY_DESCRIPTOR, SECURITY_ATTRIBUTES, TOKEN_QUERY,
            TOKEN_USER, TokenUser,
        },
        Storage::FileSystem::{
            CREATE_NEW, CreateFileW, FILE_FLAG_FIRST_PIPE_INSTANCE, FILE_FLAGS_AND_ATTRIBUTES,
            FILE_GENERIC_WRITE, PIPE_ACCESS_DUPLEX, ReadFile, WriteFile,
        },
        System::{
            Pipes::{
                ConnectNamedPipe, CreateNamedPipeW, PIPE_NOWAIT, PIPE_READMODE_BYTE,
                PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE,
            },
            Threading::{GetCurrentProcess, OpenProcessToken},
        },
    },
    core::{PCWSTR, PWSTR},
};
fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(Some(0)).collect()
}
struct Security(usize);
impl Security {
    fn current_user() -> anyhow::Result<Self> {
        unsafe {
            let mut token = HANDLE::default();
            OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token)?;
            let token = OwnedHandle::from_raw_handle(token.0);
            let mut required = 0;
            let _ = GetTokenInformation(
                HANDLE(token.as_raw_handle()),
                TokenUser,
                None,
                0,
                &mut required,
            );
            anyhow::ensure!((1..=65536).contains(&required), "invalid token size");
            let mut buffer =
                vec![0usize; (required as usize).div_ceil(std::mem::size_of::<usize>())];
            GetTokenInformation(
                HANDLE(token.as_raw_handle()),
                TokenUser,
                Some(buffer.as_mut_ptr().cast()),
                required,
                &mut required,
            )?;
            let user = &*buffer.as_ptr().cast::<TOKEN_USER>();
            let mut text = PWSTR::null();
            ConvertSidToStringSidW(user.User.Sid, &mut text)?;
            let sid = text.to_string();
            LocalFree(Some(HLOCAL(text.0.cast())));
            let sid = sid?;
            let sddl = wide(&format!("D:P(A;;GA;;;{sid})"));
            let mut descriptor = PSECURITY_DESCRIPTOR::default();
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                PCWSTR(sddl.as_ptr()),
                1,
                &mut descriptor,
                None,
            )?;
            Ok(Self(descriptor.0 as usize))
        }
    }
    fn attributes(&self) -> SECURITY_ATTRIBUTES {
        SECURITY_ATTRIBUTES {
            nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: self.0 as *mut _,
            bInheritHandle: false.into(),
        }
    }
}
impl Drop for Security {
    fn drop(&mut self) {
        unsafe {
            LocalFree(Some(HLOCAL(self.0 as *mut _)));
        }
    }
}
pub struct Listener {
    name: Vec<u16>,
    descriptor: PathBuf,
    security: Security,
    pending: Option<OwnedHandle>,
}
impl Listener {
    pub fn bind(nonce: &str, token: &str, bundle_id: &str) -> anyhow::Result<Self> {
        let directory = PathBuf::from(
            std::env::var_os("LOCALAPPDATA")
                .ok_or_else(|| anyhow::anyhow!("LOCALAPPDATA missing"))?,
        )
        .join("SpaceSniffer/control");
        std::fs::create_dir_all(&directory)?;
        let stem = format!("{}-{nonce}", std::process::id());
        let pipe = format!(r"\\.\pipe\space-sniffer-{stem}");
        let descriptor = directory.join(format!("{stem}.json"));
        let security = Security::current_user()?;
        let mut result = Self {
            name: wide(&pipe),
            descriptor,
            security,
            pending: None,
        };
        result.pending = Some(result.create(true)?);
        let data = serde_json::to_vec(
            &serde_json::json!({"pid":std::process::id(),"bundle_id":bundle_id,"pipe":pipe,"token":token,"version":1,"ui":"gpui"}),
        )?;
        let path = wide(&result.descriptor.to_string_lossy());
        let attributes = result.security.attributes();
        unsafe {
            let handle = CreateFileW(
                PCWSTR(path.as_ptr()),
                FILE_GENERIC_WRITE.0,
                windows::Win32::Storage::FileSystem::FILE_SHARE_MODE(0),
                Some(&attributes),
                CREATE_NEW,
                FILE_FLAGS_AND_ATTRIBUTES(0),
                None,
            )?;
            let mut file = std::fs::File::from_raw_handle(handle.0);
            file.write_all(&data)?;
        }
        Ok(result)
    }
    fn create(&self, first: bool) -> io::Result<OwnedHandle> {
        let attributes = self.security.attributes();
        let mut mode = PIPE_ACCESS_DUPLEX;
        if first {
            mode |= FILE_FLAG_FIRST_PIPE_INSTANCE;
        }
        let handle = unsafe {
            CreateNamedPipeW(
                PCWSTR(self.name.as_ptr()),
                mode,
                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS,
                4,
                65536,
                65536,
                15000,
                Some(&attributes),
            )
        };
        if handle.is_invalid() {
            return Err(io::Error::last_os_error());
        }
        Ok(unsafe { OwnedHandle::from_raw_handle(handle.0) })
    }
    pub fn cleanup_paths(&self) -> Vec<PathBuf> {
        vec![self.descriptor.clone()]
    }
    pub fn accept(&mut self) -> io::Result<Option<Stream>> {
        if self.pending.is_none() {
            match self.create(false) {
                Ok(pipe) => self.pending = Some(pipe),
                Err(_) => return Ok(None),
            }
        }
        let handle = HANDLE(self.pending.as_ref().unwrap().as_raw_handle());
        let result = unsafe { ConnectNamedPipe(handle, None) };
        match result {
            Ok(()) => Ok(Some(Stream(self.pending.take().unwrap()))),
            Err(error) if error.code() == ERROR_PIPE_CONNECTED.to_hresult() => {
                Ok(Some(Stream(self.pending.take().unwrap())))
            }
            Err(error) if error.code() == ERROR_PIPE_LISTENING.to_hresult() => Ok(None),
            Err(_) => {
                self.pending = None;
                Ok(None)
            }
        }
    }
}
impl Drop for Listener {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.descriptor);
    }
}
pub struct Stream(OwnedHandle);
impl Read for Stream {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        let start = Instant::now();
        loop {
            let mut count = 0;
            let result = unsafe {
                ReadFile(
                    HANDLE(self.0.as_raw_handle()),
                    Some(buffer),
                    Some(&mut count),
                    None,
                )
            };
            match result {
                Ok(()) if count > 0 => return Ok(count as usize),
                Err(e) if e.code() == ERROR_BROKEN_PIPE.to_hresult() => return Ok(0),
                Err(e) if e.code() != ERROR_NO_DATA.to_hresult() => {
                    return Err(io::Error::other(e));
                }
                _ => {}
            }
            if start.elapsed() > Duration::from_secs(15) {
                return Err(io::ErrorKind::TimedOut.into());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }
}
impl Write for Stream {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        let start = Instant::now();
        loop {
            let mut count = 0;
            unsafe {
                WriteFile(
                    HANDLE(self.0.as_raw_handle()),
                    Some(buffer),
                    Some(&mut count),
                    None,
                )
            }
            .map_err(io::Error::other)?;
            if count > 0 || buffer.is_empty() {
                return Ok(count as usize);
            }
            if start.elapsed() > Duration::from_secs(15) {
                return Err(io::ErrorKind::TimedOut.into());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
#[cfg(test)]
pub fn test_connect(descriptor: &serde_json::Value) -> io::Result<std::fs::File> {
    std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(descriptor["pipe"].as_str().unwrap())
}
