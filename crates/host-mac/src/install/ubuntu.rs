//! Ubuntu for ARM: the official installer and its published checksums, and the answers its
//! installer reads (cloud-init's autoinstall), in the shape the other hosts use
//! (`crates/host-windows/guest/linux/user-data` of the public repo).
//!
//! The installer is Ubuntu's own: the live server image for arm64 from `cdimage.ubuntu.com`, with
//! the `SHA256SUMS` beside it. The driver step is a named placeholder (`DRIVER_PLACEHOLDER`)
//! until the Linux guest driver is packaged; `notes/mac-app-install.md` lists what it needs.

/// Ubuntu's release folder for arm64 and its checksum list.
pub const RELEASE_URL: &str = "https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/";
pub const SUMS_FILE: &str = "SHA256SUMS";
/// The server image's name begins and ends so; the `+largemem` kernel's image shares the ending
/// and is left out.
const PREFIX: &str = "ubuntu-26.04";
const SUFFIX: &str = "-live-server-arm64.iso";

/// What the guest says on the serial port, as the other hosts' autoinstall does.
pub const FINISHED: &str = "guesthouse-install-finished";
pub const FAILED: &str = "guesthouse-install-failed";

/// Said when the driver step is reached: the Linux guest driver is not something this app can put
/// in yet.
pub const DRIVER_PLACEHOLDER: &str = "The Guesthouse graphics driver for Ubuntu is not packaged yet, so it cannot be installed. Open Ubuntu without it for now.";

/// The image to fetch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Image {
    pub name: String,
    pub sha256: String,
    pub url: String,
}

/// The server image for arm64 named in Ubuntu's checksum list, with the checksum it publishes: the
/// newest point release in the list. The folder lists a release and its point releases together
/// (`ubuntu-26.04-...` and `ubuntu-26.04.1-...`, and a `.2` when it comes), so the highest point
/// number wins, and the `+largemem` image and every other architecture are left out. A line is
/// `SHA256 *NAME` (binary) or `SHA256  NAME`.
pub fn pick_image(sums: &str) -> Result<Image, String> {
    let mut best: Option<(u32, Image)> = None;
    for line in sums.lines() {
        let Some((sum, name)) = line.split_once(' ') else {
            continue;
        };
        let name = name.trim_start_matches([' ', '*']).trim();
        let Some(point) = point_release(name) else {
            continue;
        };
        if sum.len() != 64 || !sum.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(format!("Ubuntu's checksum for {name} is not a SHA-256."));
        }
        if best.as_ref().is_none_or(|(known, _)| point > *known) {
            best = Some((
                point,
                Image {
                    name: name.to_string(),
                    sha256: sum.to_ascii_lowercase(),
                    url: format!("{RELEASE_URL}{name}"),
                },
            ));
        }
    }
    best.map(|(_, image)| image)
        .ok_or_else(|| "Ubuntu's list of checksums has no arm64 server image in it.".into())
}

/// The point release of a plain arm64 server image's name: 0 for `ubuntu-26.04-live-server-arm64.iso`,
/// 1 for `ubuntu-26.04.1-...`. Nothing for any other name (another image, another release).
fn point_release(name: &str) -> Option<u32> {
    let middle = name.strip_prefix(PREFIX)?.strip_suffix(SUFFIX)?;
    if middle.is_empty() {
        return Some(0);
    }
    let digits = middle.strip_prefix('.')?;
    (!digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()))
        .then(|| digits.parse().ok())
        .flatten()
}

fn yaml(text: &str) -> String {
    format!("'{}'", text.replace('\'', "''"))
}

/// The autoinstall answers: no questions, the largest disk, an account named after the Mac's user
/// and the password it was given (set at the end, so the first console sign-in uses it), and what is said
/// on the serial port when it ends.
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
    - echo {finished} > /dev/ttyAMA0
",
        host = hostname,
        user = account,
        password = password,
        failed = FAILED,
        finished = FINISHED,
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
