//! Getting a file from the network: with room checked first, a download that goes on from where
//! it stopped, and a checksum before the file is kept. The network is behind `Transport`, so the
//! rest runs in tests with no network; `CurlTransport` is the real one (the system's `curl`, as
//! the other hosts use).

use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// What a failed fetch says, with a code when the cause has one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FetchError {
    pub code: Option<String>,
    pub message: String,
}

impl FetchError {
    pub fn new(message: impl Into<String>) -> FetchError {
        FetchError {
            code: None,
            message: message.into(),
        }
    }
}

/// What a server says about a file before it is fetched.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Head {
    pub length: u64,
    /// Whether it takes a request for the part from a given byte on.
    pub ranges: bool,
}

pub trait Transport {
    fn head(&mut self, url: &str) -> Result<Head, FetchError>;
    /// Writes the file from byte `from` to `out`. `progress` is told how many bytes of this call
    /// have been written and says whether to go on; false stops it, with no error.
    fn get_from(
        &mut self,
        url: &str,
        from: u64,
        out: &mut dyn Write,
        progress: &mut dyn FnMut(u64) -> bool,
    ) -> Result<(), FetchError>;
    /// A small text file, such as a list of checksums.
    fn text(&mut self, url: &str) -> Result<String, FetchError>;
}

/// The room the Mac has on the disk that holds `path`, in bytes.
pub fn free_bytes(path: &Path) -> Option<u64> {
    let name = std::ffi::CString::new(path.as_os_str().as_encoded_bytes()).ok()?;
    // SAFETY: `name` is a nul-terminated path, and `stats` is plain data the call fills in.
    let stats = unsafe {
        let mut stats: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(name.as_ptr(), &mut stats) != 0 {
            return None;
        }
        stats
    };
    Some(stats.f_bavail as u64 * stats.f_frsize)
}

/// Why a download could not be finished.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    /// The file, checked, in its place.
    Done(PathBuf),
    /// The person stopped it. What was fetched is kept.
    Stopped,
}

/// The extra room asked for beyond the file, so a nearly full disk does not fail at the end.
const ROOM_MARGIN: u64 = 256 * 1024 * 1024;
/// How often the checksum is read in, in bytes.
const READ_CHUNK: usize = 1024 * 1024;

pub struct Request<'a> {
    pub url: &'a str,
    /// The folder the file goes in, which is made if need be.
    pub folder: &'a Path,
    pub name: &'a str,
    /// The file's SHA-256 as its publisher gives it, in hex.
    pub sha256: &'a str,
}

fn checked_marker(file: &Path) -> PathBuf {
    file.with_file_name(format!(
        "{}.sha256",
        file.file_name()
            .map(|n| n.to_string_lossy())
            .unwrap_or_default()
    ))
}

/// The SHA-256 of a file, in lower-case hex.
pub fn sha256_of(path: &Path) -> std::io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; READ_CHUNK];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect())
}

/// Fetches the file, going on from a part kept earlier when the server takes ranges, and keeps it
/// only if its checksum is the one given. `progress(done, total)` is told the bytes so far and
/// says whether to go on.
pub fn download(
    transport: &mut dyn Transport,
    request: &Request,
    progress: &mut dyn FnMut(u64, u64) -> bool,
) -> Result<Outcome, FetchError> {
    require_https(request.url)?;
    fs::create_dir_all(request.folder)
        .map_err(|e| FetchError::new(format!("Cannot make {}: {e}", request.folder.display())))?;
    let file = request.folder.join(request.name);
    let marker = checked_marker(&file);
    // Fetched and checked before: nothing to do.
    if file.is_file()
        && fs::read_to_string(&marker)
            .is_ok_and(|text| text.trim().eq_ignore_ascii_case(request.sha256))
    {
        return Ok(Outcome::Done(file));
    }
    let head = transport.head(request.url)?;
    let part = request.folder.join(format!("{}.part", request.name));
    let mut have = fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
    // A part that cannot be gone on from, or is longer than the file, is begun again.
    if have > head.length || (have > 0 && !head.ranges) {
        let _ = fs::remove_file(&part);
        have = 0;
    }
    let needed = head.length - have + ROOM_MARGIN;
    if let Some(free) = free_bytes(request.folder)
        && free < needed
    {
        return Err(FetchError {
            code: Some("no_space".into()),
            message: format!(
                "Not enough room on this Mac to download {}. {} more is needed.",
                request.name,
                gigabytes(needed - free)
            ),
        });
    }
    if have < head.length {
        let mut out = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&part)
            .map_err(|e| FetchError::new(format!("Cannot write {}: {e}", part.display())))?;
        let mut go_on = true;
        transport.get_from(request.url, have, &mut out, &mut |written| {
            go_on = progress(have + written, head.length);
            go_on
        })?;
        out.flush().map_err(|e| FetchError::new(e.to_string()))?;
        if !go_on {
            return Ok(Outcome::Stopped);
        }
    }
    let got = fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
    if got != head.length {
        return Err(FetchError::new(format!(
            "The download stopped at {got} of {} bytes.",
            head.length
        )));
    }
    let sum = sha256_of(&part)
        .map_err(|e| FetchError::new(format!("Cannot read {}: {e}", part.display())))?;
    if !sum.eq_ignore_ascii_case(request.sha256) {
        // What was fetched is not what the publisher published; none of it is kept.
        let _ = fs::remove_file(&part);
        return Err(FetchError {
            code: Some("checksum".into()),
            message: format!(
                "{} did not match its published checksum, so it was thrown away.",
                request.name
            ),
        });
    }
    fs::rename(&part, &file).map_err(|e| FetchError::new(e.to_string()))?;
    let _ = fs::write(&marker, format!("{sum}\n"));
    Ok(Outcome::Done(file))
}

/// "12.4 GB", for the sentences about room.
pub fn gigabytes(bytes: u64) -> String {
    format!("{:.1} GB", bytes as f64 / 1_000_000_000.0)
}

/// What a fetch is refused with when its address is not https.
pub const NOT_HTTPS: &str = "not_https";

/// Refuses any address that is not https. Everything the app downloads (an installer, its checksums,
/// the driver's manifest and files) goes over https only, and a redirect to anything else is refused
/// too (curl is told so, below).
pub fn require_https(url: &str) -> Result<(), FetchError> {
    if url.len() > "https://".len() && url[.."https://".len()].eq_ignore_ascii_case("https://") {
        return Ok(());
    }
    Err(FetchError {
        code: Some(NOT_HTTPS.into()),
        message: format!("{url} is not an https address, so it is not fetched."),
    })
}

/// What curl is run with, before the address: only https, also after a redirect.
pub const CURL_ARGS: [&str; 8] = [
    "--fail",
    "--location",
    "--silent",
    "--show-error",
    "--proto",
    "=https",
    "--proto-redir",
    "=https",
];

/// The real network: the system's `curl`.
pub struct CurlTransport;

impl CurlTransport {
    fn curl() -> Command {
        let mut command = Command::new("curl");
        command.args(CURL_ARGS);
        command.stdin(Stdio::null());
        command
    }
}

impl Transport for CurlTransport {
    fn head(&mut self, url: &str) -> Result<Head, FetchError> {
        require_https(url)?;
        let output = Self::curl()
            .args(["--head", url])
            .output()
            .map_err(|e| FetchError::new(format!("curl could not be started: {e}")))?;
        if !output.status.success() {
            return Err(FetchError::new(format!(
                "{url} could not be reached: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            )));
        }
        let headers = String::from_utf8_lossy(&output.stdout).to_ascii_lowercase();
        // After redirects the last answer's headers count, so read from the end.
        let length = headers
            .lines()
            .rev()
            .find_map(|line| {
                line.strip_prefix("content-length:")?
                    .trim()
                    .parse::<u64>()
                    .ok()
            })
            .ok_or_else(|| FetchError::new(format!("{url} did not say how big it is.")))?;
        let ranges = headers
            .lines()
            .any(|line| line.trim() == "accept-ranges: bytes");
        Ok(Head { length, ranges })
    }

    fn get_from(
        &mut self,
        url: &str,
        from: u64,
        out: &mut dyn Write,
        progress: &mut dyn FnMut(u64) -> bool,
    ) -> Result<(), FetchError> {
        require_https(url)?;
        let mut command = Self::curl();
        if from > 0 {
            command.args(["--range", &format!("{from}-")]);
        }
        let mut child = command
            .arg(url)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| FetchError::new(format!("curl could not be started: {e}")))?;
        let mut body = child.stdout.take().expect("piped");
        let (mut buffer, mut written) = (vec![0u8; READ_CHUNK], 0u64);
        loop {
            let read = body
                .read(&mut buffer)
                .map_err(|e| FetchError::new(e.to_string()))?;
            if read == 0 {
                break;
            }
            out.write_all(&buffer[..read])
                .map_err(|e| FetchError::new(format!("Cannot write the download: {e}")))?;
            written += read as u64;
            if !progress(written) {
                let _ = child.kill();
                let _ = child.wait();
                return Ok(());
            }
        }
        let status = child.wait().map_err(|e| FetchError::new(e.to_string()))?;
        if !status.success() {
            let mut said = String::new();
            if let Some(mut err) = child.stderr.take() {
                let _ = err.read_to_string(&mut said);
            }
            return Err(FetchError::new(format!(
                "The download stopped: {}",
                said.trim()
            )));
        }
        Ok(())
    }

    fn text(&mut self, url: &str) -> Result<String, FetchError> {
        require_https(url)?;
        let output = Self::curl()
            .arg(url)
            .output()
            .map_err(|e| FetchError::new(format!("curl could not be started: {e}")))?;
        if !output.status.success() {
            return Err(FetchError::new(format!(
                "{url} could not be read: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            )));
        }
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    }
}

#[cfg(test)]
mod tests;
