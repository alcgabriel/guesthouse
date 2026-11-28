// SPDX-License-Identifier: GPL-2.0-or-later
//! LAB ONLY. The places on the lab's Mac where the programs the app runs are built, tried after
//! every other place, so the app finds them with nothing set up while it is developed there.
//!
//! All of it is behind the `lab` feature, which `build-core.sh` turns on only inside the lab's
//! tree. Without the feature nothing here names a path, so a public build has none of this Mac's
//! places in it, and the whole file can be deleted with `mod lab;` and the calls to it.
//!
//! Every path is under the home folder. Each list is in the order tried, newest first.

use crate::tools::Tool;
use std::path::{Path, PathBuf};

#[cfg(feature = "lab")]
mod paths {
    pub const QEMU: &[&str] = &[
        "Developer/lab/m5/build/rmhost/qemu-windows/qemu-system-aarch64",
    ];
    pub const RMHOST: &[&str] =
        &["Developer/lab/m5/build/rmhost/rmhost"];
    /// The contributor's build (a library with a thin main, both sockets 0600, the frame export
    /// built in), which the lab's run.sh uses by default; then the earlier separate frame-export
    /// build. The stock build in build/guesthouse has no --frames and is refused.
    pub const PVG_HOST: &[&str] = &[
        "Developer/lab/m5/build/guesthouse-adcafeb/release/guesthouse-pvg-host",
        "Developer/lab/m5/.tools/m4-frame-export/target/release/guesthouse-pvg-host",
    ];
    pub const PVG_QEMU: &[&str] = &[
        "Developer/lab/m5/build/qemu-pvg/qemu/qemu-system-aarch64",
    ];
    /// QEMU's firmware, beside the lab's QEMU build.
    pub const FIRMWARE: &str =
        "Developer/lab/m5/.tools/src/qemu-build/pc-bios";
    /// The script that makes the driver's disk.
    pub const STICK_SCRIPT: &str = "Developer/lab/win/stick.sh";
}

/// The lab's builds of `tool` under `home`, newest first; none without the `lab` feature.
pub fn builds(tool: Tool, home: &Path) -> Vec<PathBuf> {
    #[cfg(feature = "lab")]
    {
        let list = match tool {
            Tool::Qemu => paths::QEMU,
            Tool::Rmhost => paths::RMHOST,
            Tool::PvgHost => paths::PVG_HOST,
            Tool::PvgQemu => paths::PVG_QEMU,
        };
        list.iter().map(|path| home.join(path)).collect()
    }
    #[cfg(not(feature = "lab"))]
    {
        let _ = (tool, home);
        Vec::new()
    }
}

/// QEMU's firmware folder in the lab, if this is a lab build.
pub fn firmware_dir(home: &Path) -> Option<PathBuf> {
    #[cfg(feature = "lab")]
    return Some(home.join(paths::FIRMWARE));
    #[cfg(not(feature = "lab"))]
    {
        let _ = home;
        None
    }
}

/// The lab's `stick.sh`, if this is a lab build.
pub fn stick_script(home: &Path) -> Option<PathBuf> {
    #[cfg(feature = "lab")]
    return Some(home.join(paths::STICK_SCRIPT));
    #[cfg(not(feature = "lab"))]
    {
        let _ = home;
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(feature = "lab")]
    #[test]
    fn the_newer_graphics_process_is_tried_first() {
        let list = builds(Tool::PvgHost, Path::new("/h"));
        assert!(list[0].ends_with("guesthouse-adcafeb/release/guesthouse-pvg-host"));
        assert_eq!(list.len(), 2);
    }

    #[cfg(not(feature = "lab"))]
    #[test]
    fn a_public_build_names_no_lab_place() {
        for tool in [Tool::Qemu, Tool::Rmhost, Tool::PvgHost, Tool::PvgQemu] {
            assert!(builds(tool, Path::new("/h")).is_empty());
        }
        assert!(firmware_dir(Path::new("/h")).is_none());
        assert!(stick_script(Path::new("/h")).is_none());
    }
}
