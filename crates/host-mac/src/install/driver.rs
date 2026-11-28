//! The graphics driver's package for a Windows guest, as a release publishes it, and how it is got.
//!
//! **What a release must produce** (written down for whoever builds releases; `notes/mac-app-install.md`
//! has it too). The signing happens where releases are built, with a key that never leaves there
//! and is not in git. The package carries only what the guest needs to trust and load the driver:
//!
//! - `install.ps1`: trusts the certificate, turns test signing on and installs the driver from its
//!   own folder (`pnputil /add-driver ruxnwddm-full.inf /install`), says how it went on the serial
//!   port, and exits with Windows' error code if it failed. It signs nothing. A draft is in
//!   `scripts/mac/release/`, with the script that lays the package out.
//! - `ruxnwddm.sys`, `ruxnwddm-full.inf`, `ruxnwddm-full.cat`: the kernel driver, already signed.
//! - `ruxnumd.dll`, `winemetal.dll`, `ruxndxgi.dll`, `ruxnd3d11.dll`: the user-mode driver and what
//!   it draws with (the INF's `[SourceDisksFiles]`), already signed in the catalog.
//! - `ruxn-driver.cer`: the public certificate the driver is signed with, and nothing private.
//!
//! and a manifest, `guesthouse-windows-driver-latest.json`, published beside them:
//!
//! ```json
//! {"version": "0.3.36", "files": [
//!   {"name": "guesthouse-windows-driver-0.3.36-ruxnwddm.sys", "as": "ruxnwddm.sys", "sha256": "..."}
//! ]}
//! ```
//!
//! Everything is at `files.ruxn.com/p/guesthouse/<name>`, the owner's file site, which serves a
//! project's published files flat at `/p/<project>/<file>` (the layout the other hosts' releases
//! use). `name` is the published file name (with the version in it); `as` is its name in the
//! package. The guest's install puts the certificate in the guest's trusted stores and turns test
//! signing on by itself, so the tester never handles a certificate.
//!
//! `GUESTHOUSE_DRIVER_DIR` names a folder of the same files instead, for the lab.

use super::fetch::{self, FetchError, Outcome, Request, Transport};
use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};

/// Where the owner's file site serves the guesthouse project's published files.
pub const BASE_URL: &str = "https://files.ruxn.com/p/guesthouse/";
pub const MANIFEST_NAME: &str = "guesthouse-windows-driver-latest.json";

/// What the package must hold, by the name each has in it.
pub const SCRIPT: &str = "install.ps1";
pub const CERTIFICATE: &str = "ruxn-driver.cer";
pub const REQUIRED: [&str; 9] = [
    SCRIPT,
    CERTIFICATE,
    "ruxnwddm.sys",
    "ruxnwddm-full.inf",
    "ruxnwddm-full.cat",
    "ruxnumd.dll",
    "winemetal.dll",
    "ruxndxgi.dll",
    "ruxnd3d11.dll",
];

/// Files that hold a private key. A package with one is refused, whoever made it.
const PRIVATE_KEY_ENDINGS: [&str; 5] = [".pfx", ".p12", ".pvk", ".key", ".snk"];

#[derive(Debug, Deserialize, PartialEq, Eq)]
pub struct Manifest {
    pub version: String,
    pub files: Vec<Entry>,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    #[serde(rename = "as")]
    pub package_name: String,
    pub sha256: String,
}

impl Manifest {
    /// Reads a manifest and checks it names every file the package needs, once each, with
    /// names that stay in their folder, checksums that are SHA-256 and no private key.
    pub fn parse(text: &str) -> Result<Manifest, String> {
        let manifest: Manifest = serde_json::from_str(text)
            .map_err(|e| format!("The driver's manifest is not readable: {e}"))?;
        for entry in &manifest.files {
            for name in [&entry.name, &entry.package_name] {
                if name.is_empty() || name.contains(['/', '\\']) || name.starts_with('.') {
                    return Err(format!(
                        "The driver's manifest names {name:?}, which is not a file name."
                    ));
                }
            }
            if entry.sha256.len() != 64 || !entry.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
                return Err(format!(
                    "The driver's manifest has no SHA-256 for {}.",
                    entry.name
                ));
            }
        }
        for needed in REQUIRED {
            let count = manifest
                .files
                .iter()
                .filter(|e| e.package_name == needed)
                .count();
            if count != 1 {
                return Err(format!(
                    "The driver's manifest must name {needed} once, and it names it {count} times."
                ));
            }
        }
        refuse_private_keys(manifest.files.iter().map(|e| e.package_name.as_str()))?;
        Ok(manifest)
    }
}

fn refuse_private_keys<'a>(names: impl Iterator<Item = &'a str>) -> Result<(), String> {
    for name in names {
        let lower = name.to_ascii_lowercase();
        if PRIVATE_KEY_ENDINGS
            .iter()
            .any(|ending| lower.ends_with(ending))
        {
            return Err(format!(
                "The driver's package has {name}, which looks like a private key. Packages carry the public certificate only."
            ));
        }
    }
    Ok(())
}

/// Where a fetched package is kept: one folder for the version, with the manifest beside it.
fn folder_of(downloads: &Path, version: &str) -> PathBuf {
    downloads.join("windows-driver").join(version)
}

/// Fetches the manifest and every file it names into `downloads`, each checked against its
/// SHA-256, and returns the folder holding the package under its own names.
pub fn fetch_package(
    transport: &mut dyn Transport,
    downloads: &Path,
) -> Result<PathBuf, FetchError> {
    let text = transport.text(&format!("{BASE_URL}{MANIFEST_NAME}"))?;
    let manifest = Manifest::parse(&text).map_err(FetchError::new)?;
    let folder = folder_of(downloads, &manifest.version);
    let parts = folder.join("parts");
    for entry in &manifest.files {
        let url = format!("{BASE_URL}{}", entry.name);
        let request = Request {
            url: &url,
            folder: &parts,
            name: &entry.name,
            sha256: &entry.sha256,
        };
        match fetch::download(transport, &request, &mut |_, _| true)? {
            Outcome::Done(path) => {
                fs::copy(&path, folder.join(&entry.package_name)).map_err(|e| {
                    FetchError::new(format!("Cannot keep {}: {e}", entry.package_name))
                })?;
            }
            Outcome::Stopped => return Err(FetchError::new("The driver's download was stopped.")),
        }
    }
    fs::write(folder.join(MANIFEST_NAME), text)
        .map_err(|e| FetchError::new(format!("Cannot keep the driver's manifest: {e}")))?;
    Ok(folder)
}

/// The package a fetch kept, found again and checked against its manifest, newest first. None
/// when there is none whole.
pub fn kept_package(downloads: &Path) -> Option<PathBuf> {
    let versions = fs::read_dir(downloads.join("windows-driver")).ok()?;
    let mut found: Vec<PathBuf> = versions
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.join(MANIFEST_NAME).is_file())
        .collect();
    // By version number (0.3.36 is newer than 0.3.9), not by the folder's text. A folder whose
    // name is not three numbers sorts before every version, so it is only used when it is all there is.
    found.sort_by_key(|folder| {
        folder
            .file_name()
            .and_then(|n| n.to_str())
            .and_then(version_numbers)
    });
    found.into_iter().rev().find(|folder| {
        let Ok(text) = fs::read_to_string(folder.join(MANIFEST_NAME)) else {
            return false;
        };
        Manifest::parse(&text).is_ok_and(|m| {
            m.files.iter().all(|e| {
                fetch::sha256_of(&folder.join(&e.package_name))
                    .is_ok_and(|sum| sum.eq_ignore_ascii_case(&e.sha256))
            })
        })
    })
}

/// A version's three numbers, for ordering. The shared crate's `newer` compares two; this gives
/// the numbers so a list can be sorted with them.
fn version_numbers(version: &str) -> Option<[u64; 3]> {
    if !guesthouse_update_check::is_version(version) {
        return None;
    }
    let mut parts = version
        .trim()
        .split('.')
        .map(|p| p.parse::<u64>().unwrap_or(0));
    Some([parts.next()?, parts.next()?, parts.next()?])
}

/// The files of a package folder, for the stick: every file in it, which must hold those the
/// guest needs, and none that is a private key. A folder from `GUESTHOUSE_DRIVER_DIR` is checked
/// the same way a fetched one is.
pub fn package_files(folder: &Path) -> Result<Vec<PathBuf>, String> {
    let entries = fs::read_dir(folder).map_err(|_| {
        format!(
            "The driver's files are not at {}. Build them first.",
            folder.display()
        )
    })?;
    let files: Vec<PathBuf> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.is_file())
        .filter(|p| p.file_name().is_some_and(|n| n != MANIFEST_NAME))
        .collect();
    let names: Vec<String> = files
        .iter()
        .filter_map(|f| f.file_name().map(|n| n.to_string_lossy().into_owned()))
        .collect();
    for needed in REQUIRED {
        if !names.iter().any(|n| n == needed) {
            return Err(format!(
                "The driver's files at {} have no {needed}.",
                folder.display()
            ));
        }
    }
    refuse_private_keys(names.iter().map(String::as_str))?;
    Ok(files)
}

#[cfg(test)]
mod tests;
