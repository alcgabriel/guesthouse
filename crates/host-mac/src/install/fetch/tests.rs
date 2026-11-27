// SPDX-License-Identifier: GPL-2.0-or-later
use super::*;
use sha2::{Digest, Sha256};

/// A server in memory. `break_after` ends the first call that long into the body with an error, as
/// a connection that dropped does.
struct Fake {
    content: Vec<u8>,
    ranges: bool,
    break_after: Option<u64>,
    calls: Vec<u64>,
}

impl Fake {
    fn new(content: &[u8]) -> Fake {
        Fake { content: content.to_vec(), ranges: true, break_after: None, calls: vec![] }
    }
}

impl Transport for Fake {
    fn head(&mut self, _url: &str) -> Result<Head, FetchError> {
        Ok(Head { length: self.content.len() as u64, ranges: self.ranges })
    }

    fn get_from(
        &mut self,
        _url: &str,
        from: u64,
        out: &mut dyn Write,
        progress: &mut dyn FnMut(u64) -> bool,
    ) -> Result<(), FetchError> {
        self.calls.push(from);
        let body = &self.content[from as usize..];
        let limit = self.break_after.take().map_or(body.len(), |n| (n as usize).min(body.len()));
        for (index, chunk) in body[..limit].chunks(4).enumerate() {
            out.write_all(chunk).unwrap();
            if !progress((index * 4 + chunk.len()) as u64) {
                return Ok(());
            }
        }
        if limit < body.len() {
            return Err(FetchError::new("The connection dropped."));
        }
        Ok(())
    }

    fn text(&mut self, _url: &str) -> Result<String, FetchError> {
        Ok(String::new())
    }
}

fn sum(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

fn folder(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("gh-fetch-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&path);
    path
}

fn request<'a>(folder: &'a Path, sha: &'a str) -> Request<'a> {
    Request { url: "https://example.test/file.iso", folder, name: "file.iso", sha256: sha }
}

const CONTENT: &[u8] = b"an installer, as far as these tests go, with some length to it";

#[test]
fn a_file_is_fetched_checked_and_kept_with_its_checksum() {
    let dir = folder("whole");
    let mut transport = Fake::new(CONTENT);
    let mut last = (0, 0);
    let outcome = download(&mut transport, &request(&dir, &sum(CONTENT)), &mut |done, total| {
        last = (done, total);
        true
    })
    .unwrap();
    assert_eq!(outcome, Outcome::Done(dir.join("file.iso")));
    assert_eq!(fs::read(dir.join("file.iso")).unwrap(), CONTENT);
    assert_eq!(last, (CONTENT.len() as u64, CONTENT.len() as u64));
    assert!(!dir.join("file.iso.part").exists());
    // Asked again, it is not fetched again.
    let mut again = Fake::new(b"different");
    assert!(matches!(
        download(&mut again, &request(&dir, &sum(CONTENT)), &mut |_, _| true),
        Ok(Outcome::Done(_))
    ));
    assert!(again.calls.is_empty());
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn a_dropped_connection_is_gone_on_from_where_it_stopped() {
    let dir = folder("resume");
    let mut transport = Fake::new(CONTENT);
    transport.break_after = Some(20);
    let error = download(&mut transport, &request(&dir, &sum(CONTENT)), &mut |_, _| true).unwrap_err();
    assert!(error.message.contains("dropped"));
    assert_eq!(fs::metadata(dir.join("file.iso.part")).unwrap().len(), 20);
    // The second try asks for the rest only.
    download(&mut transport, &request(&dir, &sum(CONTENT)), &mut |_, _| true).unwrap();
    assert_eq!(transport.calls, [0, 20]);
    assert_eq!(fs::read(dir.join("file.iso")).unwrap(), CONTENT);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn a_server_without_ranges_is_fetched_from_the_start() {
    let dir = folder("noranges");
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join("file.iso.part"), &CONTENT[..10]).unwrap();
    let mut transport = Fake::new(CONTENT);
    transport.ranges = false;
    download(&mut transport, &request(&dir, &sum(CONTENT)), &mut |_, _| true).unwrap();
    assert_eq!(transport.calls, [0]);
    assert_eq!(fs::read(dir.join("file.iso")).unwrap(), CONTENT);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn a_file_that_is_not_the_published_one_is_thrown_away_with_a_code() {
    let dir = folder("wrong");
    let mut transport = Fake::new(CONTENT);
    let error =
        download(&mut transport, &request(&dir, &sum(b"something else")), &mut |_, _| true).unwrap_err();
    assert_eq!(error.code.as_deref(), Some("checksum"));
    assert!(!dir.join("file.iso").exists() && !dir.join("file.iso.part").exists());
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn stopping_keeps_the_part_and_says_so() {
    let dir = folder("stop");
    let mut transport = Fake::new(CONTENT);
    let outcome = download(&mut transport, &request(&dir, &sum(CONTENT)), &mut |done, _| done < 8).unwrap();
    assert_eq!(outcome, Outcome::Stopped);
    assert!(dir.join("file.iso.part").is_file());
    assert!(!dir.join("file.iso").exists());
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn not_enough_room_is_said_with_how_much_more_is_needed_before_anything_is_fetched() {
    let dir = folder("space");
    let mut transport = Fake::new(CONTENT);
    transport.content = vec![0; 8];
    // Pretend the file is far bigger than any disk.
    struct Huge(Fake);
    impl Transport for Huge {
        fn head(&mut self, _: &str) -> Result<Head, FetchError> {
            Ok(Head { length: u64::MAX / 4, ranges: true })
        }
        fn get_from(
            &mut self,
            u: &str,
            f: u64,
            o: &mut dyn Write,
            p: &mut dyn FnMut(u64) -> bool,
        ) -> Result<(), FetchError> {
            self.0.get_from(u, f, o, p)
        }
        fn text(&mut self, u: &str) -> Result<String, FetchError> {
            self.0.text(u)
        }
    }
    let mut huge = Huge(transport);
    let error = download(&mut huge, &request(&dir, "00"), &mut |_, _| true).unwrap_err();
    assert_eq!(error.code.as_deref(), Some("no_space"));
    assert!(error.message.contains("more is needed"), "{}", error.message);
    assert!(huge.0.calls.is_empty());
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn room_is_read_from_the_disk() {
    assert!(free_bytes(&std::env::temp_dir()).unwrap() > 0);
    assert!(free_bytes(Path::new("/no/such/folder")).is_none());
    assert_eq!(gigabytes(12_400_000_000), "12.4 GB");
}

#[test]
fn only_https_addresses_are_fetched() {
    for good in ["https://example.test/a", "HTTPS://example.test/a"] {
        assert!(require_https(good).is_ok(), "{good}");
    }
    for bad in [
        "http://example.test/a",
        "ftp://example.test/a",
        "file:///etc/passwd",
        "//example.test/a",
        "https://",
        "example.test",
    ] {
        let refused = require_https(bad).unwrap_err();
        assert_eq!(refused.code.as_deref(), Some(NOT_HTTPS), "{bad}");
    }
}

#[test]
fn a_download_from_an_http_address_is_refused_before_anything_is_asked() {
    let dir = folder("http");
    let mut transport = Fake::new(CONTENT);
    let wanted = sum(CONTENT);
    let mut plain = request(&dir, &wanted);
    plain.url = "http://example.test/file.iso";
    let refused = download(&mut transport, &plain, &mut |_, _| true).unwrap_err();
    assert_eq!(refused.code.as_deref(), Some(NOT_HTTPS));
    assert!(transport.calls.is_empty(), "nothing was fetched");
    assert!(!dir.join("file.iso").exists());
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn curl_is_told_to_refuse_http_and_a_redirect_to_it() {
    let args = CURL_ARGS.join(" ");
    assert!(args.contains("--proto =https"));
    assert!(args.contains("--proto-redir =https"));
    assert!(args.contains("--location"), "redirects are followed, within https");
}

#[test]
fn the_real_transport_refuses_http_without_starting_curl() {
    let mut transport = CurlTransport;
    assert_eq!(transport.text("http://example.test/x").unwrap_err().code.as_deref(), Some(NOT_HTTPS));
    assert_eq!(transport.head("http://example.test/x").unwrap_err().code.as_deref(), Some(NOT_HTTPS));
    let mut sink = Vec::new();
    let refused = transport.get_from("http://example.test/x", 0, &mut sink, &mut |_| true);
    assert_eq!(refused.unwrap_err().code.as_deref(), Some(NOT_HTTPS));
}
