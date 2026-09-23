//! Where the control socket lives, held by descriptor.
//!
//! The daemon runs as root and acts on the socket's path several times: it
//! removes a stale socket, binds a fresh one, hands it to the launching account
//! and removes it on exit. Each of those is made relative to the socket's
//! directory, opened once and judged by what `fstat` reports for the open
//! descriptor, so no rename or link swap in any directory above can point a
//! root action at another file.
//!
//! A lock file next to the socket keeps one daemon per socket without
//! connecting to it: a probe connection would be taken as the running daemon's
//! owner, and its close would end that daemon.

use std::ffi::{CString, OsStr};
use std::io;
use std::mem::MaybeUninit;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

/// The control socket's directory, the socket's name in it, and the lock that
/// makes this daemon the only one serving it.
pub struct ControlSocket {
    path: PathBuf,
    dir: OwnedFd,
    name: CString,
    /// Held, never read: the lock lasts as long as the descriptor.
    _lock: OwnedFd,
}

impl ControlSocket {
    /// Opens the socket's directory (creating it with mode 0755 when missing)
    /// and refuses it unless [`socket_dir_is_trusted`] accepts it, takes the
    /// per-socket lock, and removes a stale socket left at the path.
    ///
    /// # Errors
    ///
    /// The directory cannot be created, opened or trusted; another daemon holds
    /// the lock; or something other than a socket sits at the path, which the
    /// daemon never removes: the path's author could otherwise have root delete
    /// any file.
    pub fn claim(path: &Path, euid: u32) -> Result<Self> {
        let name = path
            .file_name()
            .context("the socket path must name a file")?;
        let name = CString::new(name.as_bytes()).context("the socket name holds a NUL byte")?;
        let dir_path = match path.parent() {
            Some(parent) if !parent.as_os_str().is_empty() => parent,
            _ => Path::new("."),
        };
        create_dir_if_missing(dir_path)?;
        let dir = open_dir(dir_path)
            .with_context(|| format!("opening the socket directory {}", dir_path.display()))?;
        let meta = fstat(&dir)?;
        anyhow::ensure!(
            socket_dir_is_trusted(
                file_type(&meta) == libc::S_IFDIR,
                meta.st_uid,
                u32::from(meta.st_mode),
                euid
            ),
            "refusing the socket directory {}: it must be a directory owned by root or by this \
             account that no other account can write to",
            dir_path.display()
        );
        let lock = take_lock(&dir, &name, euid, path)?;
        let socket = Self {
            path: path.to_owned(),
            dir,
            name,
            _lock: lock,
        };
        socket.clear_stale()?;
        Ok(socket)
    }

    /// The socket's path, for display.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Binds the socket owner-only from creation (0600: there is no instant
    /// where another account could connect) and, when sudo launched the daemon,
    /// hands it to the invoking account (`owner` is sudo's `SUDO_UID` /
    /// `SUDO_GID`) so that account's app can connect.
    ///
    /// # Errors
    ///
    /// The bind or the hand-off fails.
    pub fn bind(&self, owner: (Option<u32>, Option<u32>)) -> Result<tokio::net::UnixListener> {
        let listener = {
            let _umask = UmaskGuard::set(0o177);
            let _cwd = CwdGuard::enter(&self.dir).context("entering the socket directory")?;
            std::os::unix::net::UnixListener::bind(OsStr::from_bytes(self.name.as_bytes()))
                .with_context(|| format!("binding the daemon socket at {}", self.path.display()))?
        };
        let (uid, gid) = owner;
        if uid.is_some() || gid.is_some() {
            // SAFETY: both pointers are valid for the call; `u32::MAX` is
            // `(uid_t)-1` / `(gid_t)-1`, which leaves that id unchanged.
            let rc = unsafe {
                libc::fchownat(
                    self.dir.as_raw_fd(),
                    self.name.as_ptr(),
                    uid.unwrap_or(u32::MAX),
                    gid.unwrap_or(u32::MAX),
                    libc::AT_SYMLINK_NOFOLLOW,
                )
            };
            if rc != 0 {
                return Err(io::Error::last_os_error())
                    .context("handing the daemon socket to the invoking account");
            }
        }
        listener.set_nonblocking(true)?;
        Ok(tokio::net::UnixListener::from_std(listener)?)
    }

    /// Removes the socket on the way out. Best-effort: the process is ending.
    pub fn remove(&self) {
        // SAFETY: both pointers are valid for the call.
        unsafe { libc::unlinkat(self.dir.as_raw_fd(), self.name.as_ptr(), 0) };
    }

    /// Removes a socket a dead predecessor left at the path. With the lock held
    /// no live daemon serves it.
    fn clear_stale(&self) -> Result<()> {
        let mut meta = MaybeUninit::<libc::stat>::uninit();
        // SAFETY: the pointers are valid and `meta` is only read on success.
        let rc = unsafe {
            libc::fstatat(
                self.dir.as_raw_fd(),
                self.name.as_ptr(),
                meta.as_mut_ptr(),
                libc::AT_SYMLINK_NOFOLLOW,
            )
        };
        if rc != 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::NotFound {
                return Ok(());
            }
            return Err(error)
                .with_context(|| format!("inspecting the socket path {}", self.path.display()));
        }
        // SAFETY: fstatat succeeded, so it filled `meta`.
        let meta = unsafe { meta.assume_init() };
        anyhow::ensure!(
            file_type(&meta) == libc::S_IFSOCK,
            "{} exists and is not a socket; refusing to replace it",
            self.path.display()
        );
        // SAFETY: both pointers are valid for the call.
        if unsafe { libc::unlinkat(self.dir.as_raw_fd(), self.name.as_ptr(), 0) } != 0 {
            return Err(io::Error::last_os_error())
                .with_context(|| format!("removing the stale socket {}", self.path.display()));
        }
        Ok(())
    }
}

/// Whether a directory may hold the control socket: a real directory owned by
/// root or by the daemon's own account that is either not writable by group or
/// others, or sticky like `/tmp`. Inside it no other account can rename or
/// replace the entries the daemon, root when it matters, acts on.
pub fn socket_dir_is_trusted(is_dir: bool, owner: u32, mode: u32, euid: u32) -> bool {
    const GROUP_OR_OTHER_WRITE: u32 = 0o022;
    const STICKY: u32 = 0o1000;
    is_dir
        && (owner == 0 || owner == euid)
        && (mode & GROUP_OR_OTHER_WRITE == 0 || mode & STICKY != 0)
}

/// Takes the exclusive lock on `<socket name>.lock` in the socket's directory.
fn take_lock(dir: &OwnedFd, name: &CString, euid: u32, path: &Path) -> Result<OwnedFd> {
    let mut lock_name = name.as_bytes().to_vec();
    lock_name.extend_from_slice(b".lock");
    let lock_name = CString::new(lock_name).context("the lock file name holds a NUL byte")?;
    // SAFETY: the pointer is valid; the returned descriptor is owned below.
    let fd = unsafe {
        libc::openat(
            dir.as_raw_fd(),
            lock_name.as_ptr(),
            libc::O_RDONLY | libc::O_CREAT | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            0o600 as libc::c_uint,
        )
    };
    if fd < 0 {
        return Err(io::Error::last_os_error())
            .with_context(|| format!("opening the lock file next to {}", path.display()));
    }
    // SAFETY: `fd` is a fresh descriptor nothing else owns.
    let lock = unsafe { OwnedFd::from_raw_fd(fd) };
    let meta = fstat(&lock)?;
    // In a sticky directory another account could have planted the lock file
    // first, or linked it to one of its files.
    anyhow::ensure!(
        file_type(&meta) == libc::S_IFREG && meta.st_nlink == 1 && meta.st_uid == euid,
        "the lock file next to {} is not this daemon's own; refusing to start",
        path.display()
    );
    // SAFETY: `lock` is a valid descriptor.
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        let error = io::Error::last_os_error();
        if error.kind() == io::ErrorKind::WouldBlock {
            anyhow::bail!(
                "another warrend is already serving {}; refusing to start",
                path.display()
            );
        }
        return Err(error).context("locking the daemon socket");
    }
    Ok(lock)
}

fn create_dir_if_missing(dir: &Path) -> Result<()> {
    use std::os::unix::fs::DirBuilderExt;

    let _umask = UmaskGuard::set(0o022);
    match std::fs::DirBuilder::new().mode(0o755).create(dir) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => Ok(()),
        Err(error) => {
            Err(error).with_context(|| format!("creating the socket directory {}", dir.display()))
        }
    }
}

/// Opens a directory without following a link in its last component.
fn open_dir(dir: &Path) -> io::Result<OwnedFd> {
    let dir = CString::new(dir.as_os_str().as_bytes())
        .map_err(|_| io::Error::from(io::ErrorKind::InvalidInput))?;
    // SAFETY: the pointer is valid; the returned descriptor is owned below.
    let fd = unsafe {
        libc::open(
            dir.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: `fd` is a fresh descriptor nothing else owns.
    Ok(unsafe { OwnedFd::from_raw_fd(fd) })
}

fn fstat(fd: &OwnedFd) -> io::Result<libc::stat> {
    let mut meta = MaybeUninit::<libc::stat>::uninit();
    // SAFETY: the pointer is valid and `meta` is only read on success.
    if unsafe { libc::fstat(fd.as_raw_fd(), meta.as_mut_ptr()) } != 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: fstat succeeded, so it filled `meta`.
    Ok(unsafe { meta.assume_init() })
}

fn file_type(meta: &libc::stat) -> libc::mode_t {
    meta.st_mode & libc::S_IFMT
}

/// The process umask while the guard lives, restored on drop. The umask is
/// process-wide, so a guard only spans a file creation made while no other
/// thread creates files.
struct UmaskGuard(libc::mode_t);

impl UmaskGuard {
    fn set(mask: libc::mode_t) -> Self {
        // SAFETY: umask only swaps this process's file-creation mask.
        Self(unsafe { libc::umask(mask) })
    }
}

impl Drop for UmaskGuard {
    fn drop(&mut self) {
        // SAFETY: as in `set`.
        unsafe { libc::umask(self.0) };
    }
}

/// The working directory moved into a directory descriptor while the guard
/// lives, and to `/` on drop. Binding a bare name there is the portable way to
/// bind relative to a descriptor (there is no `bindat` on macOS). Process-wide
/// like the umask, so held only across the bind, while no other thread uses a
/// relative path.
struct CwdGuard;

impl CwdGuard {
    fn enter(dir: &OwnedFd) -> io::Result<Self> {
        // SAFETY: `dir` is a valid directory descriptor.
        if unsafe { libc::fchdir(dir.as_raw_fd()) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self)
    }
}

impl Drop for CwdGuard {
    fn drop(&mut self) {
        // SAFETY: the path is a valid C string.
        unsafe { libc::chdir(c"/".as_ptr()) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_socket_directory_is_trusted_only_when_no_other_account_can_swap_its_entries() {
        const ROOT: u32 = 0;
        const LAUNCHER: u32 = 501;

        // A root daemon: its own run directory, and /tmp (sticky, so only an
        // entry's owner can rename or remove it).
        assert!(socket_dir_is_trusted(true, ROOT, 0o755, ROOT));
        assert!(socket_dir_is_trusted(true, ROOT, 0o1777, ROOT));
        // An unprivileged daemon in its own private directory.
        assert!(socket_dir_is_trusted(true, LAUNCHER, 0o700, LAUNCHER));

        // A root daemon pointed at a directory its launcher owns: the launcher
        // could swap the socket for a link between bind and the ownership
        // hand-off, and have root chown any file to itself.
        assert!(!socket_dir_is_trusted(true, LAUNCHER, 0o700, ROOT));
        assert!(!socket_dir_is_trusted(true, ROOT, 0o775, ROOT));
        assert!(!socket_dir_is_trusted(true, ROOT, 0o777, ROOT));
        // A symlink (the descriptor was opened without following it) or a file.
        assert!(!socket_dir_is_trusted(false, ROOT, 0o755, ROOT));
    }
}
