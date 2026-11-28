// SPDX-License-Identifier: GPL-2.0-or-later
//! Stand-ins for what an install finds on a developer's Mac, so the tests need nothing outside
//! the checkout: QEMU's firmware files and the script that makes the driver's disk.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

/// Makes `root/firmware` with the files an install looks for, and `root/stick.sh`, which makes an
/// empty image for `new` and takes `put` without doing anything. Returns both paths.
pub fn stand_ins(root: &Path) -> (PathBuf, PathBuf) {
    let firmware = root.join("firmware");
    fs::create_dir_all(&firmware).unwrap();
    for name in ["edk2-aarch64-code.fd", "edk2-aarch64-vars.fd", "pvgfb.rom"] {
        fs::write(firmware.join(name), "x").unwrap();
    }
    let script = root.join("stick.sh");
    fs::write(&script, "#!/bin/sh\ncase $1 in new) : > \"$2\";; esac\n").unwrap();
    fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();
    (firmware, script)
}
