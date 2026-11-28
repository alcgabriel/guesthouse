// SPDX-License-Identifier: GPL-2.0-or-later
use super::*;
use crate::install::fake::FakeNetwork;
use std::fs;
use std::process::Command;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("gh-drv-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn manifest_with(files: &[(&str, &str)]) -> String {
    let entries: Vec<String> = files
        .iter()
        .map(|(name, sum)| format!(r#"{{"name":"p-{name}","as":"{name}","sha256":"{sum}"}}"#))
        .collect();
    format!(r#"{{"version":"1","files":[{}]}}"#, entries.join(","))
}

const SUM: &str = "0000000000000000000000000000000000000000000000000000000000000000";

#[test]
fn a_manifest_must_name_each_needed_file_once_with_a_sha256() {
    let whole: Vec<(&str, &str)> = REQUIRED.iter().map(|n| (*n, SUM)).collect();
    assert!(Manifest::parse(&manifest_with(&whole)).is_ok());
    assert!(
        Manifest::parse(&manifest_with(&whole[1..]))
            .unwrap_err()
            .contains("install.ps1")
    );
    let mut twice = whole.clone();
    twice.push(("ruxnwddm.sys", SUM));
    assert!(
        Manifest::parse(&manifest_with(&twice))
            .unwrap_err()
            .contains("2 times")
    );
    let mut short = whole.clone();
    short[0].1 = "abc";
    assert!(
        Manifest::parse(&manifest_with(&short))
            .unwrap_err()
            .contains("SHA-256")
    );
    assert!(Manifest::parse("not json").is_err());
}

#[test]
fn a_name_that_leaves_its_folder_or_a_private_key_is_refused() {
    let mut files: Vec<(&str, &str)> = REQUIRED.iter().map(|n| (*n, SUM)).collect();
    files.push(("../escape", SUM));
    assert!(
        Manifest::parse(&manifest_with(&files))
            .unwrap_err()
            .contains("not a file name")
    );
    let mut files: Vec<(&str, &str)> = REQUIRED.iter().map(|n| (*n, SUM)).collect();
    files.push(("ruxn-test.pfx", SUM));
    assert!(
        Manifest::parse(&manifest_with(&files))
            .unwrap_err()
            .contains("private key")
    );
}

#[test]
fn a_fetched_package_is_whole_checked_and_found_again() {
    let downloads = scratch("fetch");
    let folder = fetch_package(&mut FakeNetwork, &downloads).unwrap();
    let files = package_files(&folder).unwrap();
    assert_eq!(files.len(), REQUIRED.len());
    assert_eq!(kept_package(&downloads), Some(folder.clone()));
    // A file changed after it was kept makes the package not whole.
    fs::write(folder.join("ruxnwddm.sys"), "changed").unwrap();
    assert_eq!(kept_package(&downloads), None);
    let _ = fs::remove_dir_all(downloads);
}

#[test]
fn a_folder_of_the_labs_is_held_to_the_same_files() {
    let dir = scratch("lab");
    assert!(
        package_files(&dir.join("none"))
            .unwrap_err()
            .contains("Build them first")
    );
    for name in &REQUIRED[1..] {
        fs::write(dir.join(name), "x").unwrap();
    }
    assert!(package_files(&dir).unwrap_err().contains("install.ps1"));
    fs::write(dir.join(SCRIPT), "x").unwrap();
    assert_eq!(package_files(&dir).unwrap().len(), REQUIRED.len());
    fs::write(dir.join("lab.pfx"), "x").unwrap();
    assert!(package_files(&dir).unwrap_err().contains("private key"));
    let _ = fs::remove_dir_all(dir);
}

/// The release script that lays a package out, in the lab's tree beside the driver's build scripts.
fn package_script() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../scripts/mac/release/package.sh")
}

#[test]
fn the_release_script_lays_out_what_the_installer_reads() {
    let script = package_script();
    if !script.is_file() {
        eprintln!("the release script is not in this checkout; skipped");
        return;
    }
    let dir = scratch("script");
    let signed = dir.join("signed");
    fs::create_dir_all(&signed).unwrap();
    for name in REQUIRED.iter().filter(|n| **n != SCRIPT) {
        fs::write(signed.join(name), format!("signed {name}")).unwrap();
    }
    fs::write(
        signed.join("ruxnwddm-full.inf"),
        "DriverVer = 11/26/2026,0.3.39.0\n",
    )
    .unwrap();
    let out = dir.join("out");
    let ran = Command::new("sh")
        .arg(&script)
        .arg(&signed)
        .arg(&out)
        .output()
        .unwrap();
    assert!(
        ran.status.success(),
        "{}",
        String::from_utf8_lossy(&ran.stderr)
    );
    // The installer's own reader takes the manifest, with the version from the INF.
    let manifest = Manifest::parse(&fs::read_to_string(out.join(MANIFEST_NAME)).unwrap()).unwrap();
    assert_eq!(manifest.version, "0.3.39");
    for entry in &manifest.files {
        let sum = crate::install::fetch::sha256_of(&out.join(&entry.name)).unwrap();
        assert_eq!(sum, entry.sha256, "{}", entry.name);
        assert!(entry.name.starts_with("guesthouse-windows-driver-0.3.39-"));
        // Beside it, its .sha256 in sha256sum's format, as the other releases have.
        let beside = fs::read_to_string(out.join(format!("{}.sha256", entry.name))).unwrap();
        assert_eq!(beside, format!("{}  {}\n", entry.sha256, entry.name));
    }
    // A private key in the folder stops it.
    fs::write(signed.join("lab.pfx"), "secret").unwrap();
    let refused = Command::new("sh")
        .arg(&script)
        .arg(&signed)
        .arg(dir.join("out2"))
        .output()
        .unwrap();
    assert!(!refused.status.success());
    assert!(String::from_utf8_lossy(&refused.stderr).contains("private key"));
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn the_draft_install_script_says_the_words_the_installer_waits_for() {
    let script = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../scripts/mac/release/install.ps1");
    let Ok(text) = fs::read_to_string(&script) else {
        return;
    };
    use crate::install::windows::marker;
    assert!(text.contains(marker::DRIVER_INSTALLED));
    assert!(text.contains(marker::DRIVER_FAILED));
    assert!(text.contains("ruxn-driver.cer") && text.contains("ruxnwddm-full.inf"));
}

/// Keeps a whole package for `version`, as a fetch would: the files and a manifest naming them.
fn keep_version(downloads: &Path, version: &str) {
    let folder = downloads.join("windows-driver").join(version);
    fs::create_dir_all(&folder).unwrap();
    let mut files = Vec::new();
    for name in REQUIRED {
        fs::write(folder.join(name), name).unwrap();
        files.push(format!(
            r#"{{"name":"p-{name}","as":"{name}","sha256":"{}"}}"#,
            crate::install::fetch::sha256_of(&folder.join(name)).unwrap()
        ));
    }
    let manifest = format!(r#"{{"version":"{version}","files":[{}]}}"#, files.join(","));
    fs::write(folder.join(MANIFEST_NAME), manifest).unwrap();
}

#[test]
fn the_newest_kept_package_is_the_highest_number_not_the_last_in_the_alphabet() {
    let downloads = scratch("newest");
    for version in ["0.3.9", "0.3.36", "0.10.0", "0.9.5"] {
        keep_version(&downloads, version);
    }
    let newest = kept_package(&downloads).unwrap();
    assert_eq!(newest.file_name().unwrap(), "0.10.0");
    // And a text sort would have said 0.9.5.
    fs::remove_dir_all(newest).unwrap();
    assert_eq!(
        kept_package(&downloads).unwrap().file_name().unwrap(),
        "0.9.5"
    );
    let _ = fs::remove_dir_all(downloads);
}
