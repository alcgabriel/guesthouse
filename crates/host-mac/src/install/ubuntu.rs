//! Ubuntu for ARM: the official installer and its published checksums, and the answers its
//! installer reads (cloud-init's autoinstall), in the shape the other hosts use
//! (`crates/host-windows/guest/linux/user-data` of the public repo).
//!
//! The installer is Ubuntu's own: the live server image for arm64 from `cdimage.ubuntu.com`, with
//! the `SHA256SUMS` beside it. The firmware starts its kernel from the image with the kernel line
//! the installer needs to run on its own (`INSTALLER_COMMAND_LINE`), as the public repo's Windows
//! host does with a boot menu of its own.
//!
//! The graphics driver comes as a package (`driver::LINUX`) on a small disk labelled `RUXN`, as
//! the Windows driver does. The answers put a service into the installed system that installs it
//! from that disk when it is there, once for each version (`DRIVER_SERVICE`, `DRIVER_RUNNER`).
//! With no package, the driver step says so (`DRIVER_PLACEHOLDER`) and offers to open Ubuntu
//! without it. `notes/mac-app-install.md` has the rest.

/// Ubuntu's release folder for arm64 and its checksum list.
pub const RELEASE_URL: &str = "https://cdimage.ubuntu.com/releases/26.04/release/";
pub const SUMS_FILE: &str = "SHA256SUMS";
/// The server image's name begins and ends so; the `+largemem` kernel's image shares the ending
/// and is left out.
const PREFIX: &str = "ubuntu-26.04";
const SUFFIX: &str = "-live-server-arm64.iso";

/// What the guest says on the serial port, as the other hosts' autoinstall does.
pub const FINISHED: &str = "guesthouse-install-finished";
pub const FAILED: &str = "guesthouse-install-failed";

/// The installer's kernel and initrd, by their paths in Ubuntu's image.
pub const INSTALLER_KERNEL: &str = "casper/vmlinuz";
pub const INSTALLER_INITRD: &str = "casper/initrd";

/// The installer's kernel line. `autoinstall`, because the installer asks before it writes the
/// disk when it found its answers only on a seed (subiquity's install controller, read
/// 2026-11-27); `ds=nocloud` for the seed disc. Its console is the screen only: on the serial port
/// the installer would print each late command, the password's too, into `serial.log`. What
/// follows `---` the installed system keeps: its console on the serial port as well, so its
/// starts can be followed in `serial.log`.
pub const INSTALLER_COMMAND_LINE: &str =
    "autoinstall ds=nocloud console=tty0 --- console=ttyAMA0,115200 console=tty0";

/// What the guest says about the driver and its first start: the same words as Windows'.
pub use super::windows::marker;

/// The answer disc's two files that the installed system gets, by their names on the disc.
pub const DRIVER_SERVICE_FILE: &str = "guesthouse-driver.service";
pub const DRIVER_RUNNER_FILE: &str = "guesthouse-driver.sh";

/// The service that installs the driver from its disk when the system starts.
pub const DRIVER_SERVICE: &str = "\
[Unit]
Description=Guesthouse graphics driver, from the disk labelled RUXN
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh /usr/local/sbin/guesthouse-driver
TimeoutStartSec=30min

[Install]
WantedBy=multi-user.target
";

/// What the service runs: the package copied off its disk, its `install.sh` run as root (which
/// says on the serial port how it went), then a restart into the desktop, or a power-off when it
/// failed, so that Try Again is the next start with the disk. A version already installed is
/// not installed again. Without the disk it does nothing.
pub const DRIVER_RUNNER: &str = r#"#!/bin/sh
# Guesthouse: installs the graphics driver from the disk labelled RUXN, once for each version.
disk=/dev/disk/by-label/RUXN
mnt=/run/guesthouse-driver
state=/var/lib/guesthouse
manifest=guesthouse-linux-driver-latest.json
say() { echo "guesthouse: $*" > /dev/ttyAMA0; }
# The disk may still be on its way while the system starts.
tries=0
while [ ! -e "$disk" ]; do
    tries=$((tries + 1))
    [ "$tries" -gt 20 ] && exit 0
    sleep 1
done
mkdir -p "$mnt" "$state"
if ! mount -o ro "$disk" "$mnt"; then
    say "driver failed mount"
    systemctl --no-block poweroff
    exit 1
fi
version=$(sed -n 's/.*"version" *: *"\([^"]*\)".*//p' "$mnt/$manifest")
if [ -n "$version" ] && [ "$(cat "$state/driver-version" 2>/dev/null)" = "$version" ]; then
    umount "$mnt"
    exit 0
fi
work="$state/driver/${version:-unknown}"
rm -rf "$work"
mkdir -p "$work"
cp -R "$mnt/." "$work/"
umount "$mnt"
(cd "$work" && sh ./install.sh)
code=$?
if [ "$code" -eq 0 ]; then
    echo "$version" > "$state/driver-version"
    systemctl --no-block reboot
else
    # Only read when install.sh said nothing itself: the first line said counts.
    say "driver failed exit-$code"
    systemctl --no-block poweroff
fi
"#;

/// Said at the driver step when there is no package for Ubuntu: none published, none named.
pub const DRIVER_PLACEHOLDER: &str = "The Guesthouse graphics driver for Ubuntu is not packaged yet, so it cannot be installed. Open Ubuntu without it for now.";

/// The image to fetch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Image {
    pub name: String,
    pub sha256: String,
    pub url: String,
}

/// The server image for arm64 named in Ubuntu's checksum list, with the checksum it publishes. A
/// line is `SHA256 *NAME` (binary) or `SHA256  NAME`.
pub fn pick_image(sums: &str) -> Result<Image, String> {
    for line in sums.lines() {
        let Some((sum, name)) = line.split_once(' ') else {
            continue;
        };
        let name = name.trim_start_matches([' ', '*']).trim();
        if name.starts_with(PREFIX) && name.ends_with(SUFFIX) && !name.contains('+') {
            if sum.len() == 64 && sum.bytes().all(|b| b.is_ascii_hexdigit()) {
                return Ok(Image {
                    name: name.to_string(),
                    sha256: sum.to_ascii_lowercase(),
                    url: format!("{RELEASE_URL}{name}"),
                });
            }
            return Err(format!("Ubuntu's checksum for {name} is not a SHA-256."));
        }
    }
    Err("Ubuntu's list of checksums has no arm64 server image in it.".into())
}

fn yaml(text: &str) -> String {
    format!("'{}'", text.replace('\'', "''"))
}

/// The autoinstall answers: no questions, the largest disk, an account named after the Mac's user
/// and the password it was given (set at the end, so the first console sign-in uses it), the
/// driver's service from the answer disc, and what is said on the serial port when it ends.
pub fn user_data(account: &str, password: &str, hostname: &str) -> String {
    format!(
        "#cloud-config
autoinstall:
  version: 1
  locale: C.UTF-8
  keyboard:
    layout: us
  storage:
    layout:
      name: direct
      match:
        size: largest
  identity:
    hostname: {host}
    username: {user}
    # The installer needs a hash here; the real password is set in the late commands, where it
    # needs no hash.
    password: '$6$guesthouse$invalid'
  ssh:
    install-server: true
    allow-pw: false
  updates: security
  refresh-installer:
    update: false
  drivers:
    install: false
  user-data:
    timezone: Etc/UTC
  shutdown: poweroff
  error-commands:
    - tail -n 100 /var/log/installer/subiquity-server-debug.log > /dev/ttyAMA0 || true
    - echo {failed} > /dev/ttyAMA0
  late-commands:
    - 'curtin in-target --target=/target -- sh -c \"echo ''{user}:{password}'' | chpasswd\"'
    - mkdir -p /run/guesthouse-answers
    - mount -o ro LABEL=CIDATA /run/guesthouse-answers
    - install -D -m 0755 /run/guesthouse-answers/{runner} /target/usr/local/sbin/guesthouse-driver
    - install -D -m 0644 /run/guesthouse-answers/{service} /target/etc/systemd/system/{service}
    - curtin in-target --target=/target -- systemctl enable {service}
    - umount /run/guesthouse-answers
    - echo {finished} > /dev/ttyAMA0
",
        host = hostname,
        user = account,
        password = password,
        failed = FAILED,
        finished = FINISHED,
        runner = DRIVER_RUNNER_FILE,
        service = DRIVER_SERVICE_FILE,
    )
}

/// The seed disc's second file: it names the instance.
pub fn meta_data(machine: &str) -> String {
    format!(
        "instance-id: guesthouse-{}\nlocal-hostname: {}\n",
        machine,
        yaml(machine).trim_matches('\'')
    )
}

#[cfg(test)]
mod tests;
