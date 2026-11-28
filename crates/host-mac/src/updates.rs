//! Whether a newer Guesthouse for the Mac is out, on the shared check (`guesthouse-update-check`,
//! which the Linux and Windows hosts use): a release publishes a small file, the file says the
//! newest version, and the shared code decides what that means for the running one. This only
//! looks and says. It does not download or install anything.
//!
//! The Mac's file is `guesthouse-macos-latest.json` beside the Windows host's at the owner's file
//! site, in the shared format (`{"version": "0.2.0", "notes": "<release page>"}`). Until a Mac
//! release publishes it the file is not there, and the check says it cannot tell.

use guesthouse_update_check::{Found, LONGEST, found, parse};
use serde_json::json;
use std::process::{Command, Stdio};

/// Where a Mac release publishes the file.
pub const LATEST_URL: &str = "https://files.ruxn.com/p/guesthouse/guesthouse-macos-latest.json";
/// Where to go when the file names no release page.
pub const WEBSITE: &str = "https://guesthouse.ruxn.com";
const FETCH_SECONDS: &str = "20";

/// The latest file, fetched with the system's curl: https only, a time limit, and no more than the
/// file can be.
fn fetch_latest() -> Option<String> {
    let output = Command::new("curl")
        .args([
            "--fail",
            "--silent",
            "--location",
            "--proto",
            "=https",
            "--max-time",
            FETCH_SECONDS,
        ])
        .args(["--max-filesize", &LONGEST.to_string(), LATEST_URL])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).into_owned())
}

/// What a check found, as JSON for the app: `state` is `newer`, `latest` or `cant_tell`; with
/// `newer`, `version` and `where` (the release's page, or the website).
pub fn answer(current: &str, latest_file: Option<&str>) -> String {
    match found(current, latest_file) {
        Found::Newer(version) => {
            let page = latest_file.and_then(parse).map(|l| l.notes).filter(|n| !n.is_empty());
            json!({"state": "newer", "version": version, "where": page.unwrap_or_else(|| WEBSITE.to_owned())})
        }
        Found::Latest => json!({"state": "latest"}),
        Found::CantTell | Found::NotInstalled => json!({"state": "cant_tell"}),
    }
    .to_string()
}

/// Looks at the network once and answers as `answer` does.
pub fn check(current: &str) -> String {
    answer(current, fetch_latest().as_deref())
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = r#"{"version": "0.2.0", "notes": "https://github.com/ruxnlabs/guesthouse/releases/tag/mac-v0.2.0"}"#;

    #[test]
    fn a_newer_release_is_named_with_its_page() {
        let said: serde_json::Value = serde_json::from_str(&answer("0.1.0", Some(FILE))).unwrap();
        assert_eq!(said["state"], "newer");
        assert_eq!(said["version"], "0.2.0");
        assert_eq!(
            said["where"],
            "https://github.com/ruxnlabs/guesthouse/releases/tag/mac-v0.2.0"
        );
    }

    #[test]
    fn with_no_page_the_website_is_where() {
        let said: serde_json::Value =
            serde_json::from_str(&answer("0.1.0", Some(r#"{"version": "0.2.0"}"#))).unwrap();
        assert_eq!(said["where"], WEBSITE);
    }

    #[test]
    fn the_same_or_a_newer_copy_is_the_latest() {
        assert_eq!(answer("0.2.0", Some(FILE)), r#"{"state":"latest"}"#);
        assert_eq!(answer("0.3.0", Some(FILE)), r#"{"state":"latest"}"#);
    }

    #[test]
    fn no_file_or_a_wrong_one_cannot_tell() {
        assert_eq!(answer("0.1.0", None), r#"{"state":"cant_tell"}"#);
        assert_eq!(answer("0.1.0", Some("garbled")), r#"{"state":"cant_tell"}"#);
        // A release page that is not the project's own is never shown.
        assert_eq!(
            answer(
                "0.1.0",
                Some(r#"{"version":"0.2.0","notes":"https://example.com/"}"#)
            ),
            r#"{"state":"cant_tell"}"#
        );
    }

    #[test]
    fn the_mac_file_is_beside_the_windows_one() {
        assert!(LATEST_URL.starts_with("https://files.ruxn.com/p/guesthouse/"));
    }
}
