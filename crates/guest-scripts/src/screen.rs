//! crates/remote-view/guest/screen.ps1's choice of whether remoteman's installer runs again, and what
//! it's given when it does. The script works in C:\Guesthouse\screen and calls Windows' services, so
//! these load only its functions for that choice from the real file and run them on a folder that
//! stands in for the guest's screen folder, as the host fills it.

use crate::{Said, Scratch, quote, run, shell};
use std::fs;
use std::path::{Path, PathBuf};

const VIEWER: &str = "1111111111111111111111111111111111111111111111111111111111111111";
const PAIRED: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
/// The functions the choice is made with.
const FUNCTIONS: [&str; 3] = ["Get-InstallNote", "Test-NoteChanged", "Get-SetupArguments"];
/// How the script before viewer.txt made its note, word for word, with its trust list as `$trusted`.
const NOTE_BEFORE: &str = "((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash, (Get-FileHash -LiteralPath $trusted -Algorithm SHA256).Hash, $encoder) -join ' '";

fn screen_script() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../remote-view/guest/screen.ps1")
}

/// A guest's screen folder as the host writes it before a boot.
struct Folder {
    shell: &'static str,
    path: PathBuf,
    _scratch: Scratch,
}

impl Folder {
    fn new(shell: &'static str) -> Self {
        let scratch = Scratch::new();
        let path = scratch.path("screen");
        fs::create_dir_all(&path).unwrap();
        let folder = Self { shell, path, _scratch: scratch };
        folder.write("remoteman-host-setup.exe", "remoteman 0.1.9");
        folder.write("encoder.txt", "auto");
        // As the host writes them: the viewer's line alone, and the guest's whole list.
        folder.write("viewer.txt", &format!("{VIEWER} Guesthouse\n"));
        folder.write("trusted", &format!("{VIEWER} Guesthouse\n"));
        folder
    }

    fn write(&self, name: &str, text: &str) {
        fs::write(self.path.join(name), text).unwrap();
    }

    /// Runs `command` with the script's functions loaded and `$folder` set to this folder.
    fn run(&self, command: &str) -> Said {
        let names = FUNCTIONS.map(|name| format!("'{name}'")).join(", ");
        run(
            self.shell,
            &format!(
                "$ErrorActionPreference = 'Stop'
                $script = [System.Management.Automation.Language.Parser]::ParseFile({}, [ref]$null, [ref]$null)
                foreach ($name in {names}) {{
                    $found = $script.Find({{ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }}, $true)
                    . ([scriptblock]::Create($found.Extent.Text))
                }}
                $folder = {}
                {command}",
                quote(&screen_script()),
                quote(&self.path),
            ),
        )
    }

    /// Notes an install as the script does once the installer has run.
    fn install(&self) {
        let said = self.run(
            "Set-Content -LiteralPath (Join-Path $folder 'installed.txt') -Value (Get-InstallNote $folder) -Encoding ascii",
        );
        assert_eq!(said.code, Some(0), "{said}");
    }

    /// Whether the script would run the installer, with its service there.
    fn installs(&self) -> bool {
        let said = self.run("Write-Output \"changed $(Test-NoteChanged $folder (Get-InstallNote $folder))\"");
        match said.last() {
            "changed True" => true,
            "changed False" => false,
            _ => panic!("no answer{said}"),
        }
    }
}

#[test]
fn nothing_changed_installs_nothing() {
    let Some(shell) = shell() else { return };
    let folder = Folder::new(shell);
    assert!(folder.installs(), "never installed");
    folder.install();
    assert!(!folder.installs());
}

/// A guest installed when the trust list was the viewer's line alone, and its note made of it, isn't
/// installed again by the script that notes the viewer's line instead.
#[test]
fn a_guest_installed_before_keeps_its_note() {
    let Some(shell) = shell() else { return };
    let folder = Folder::new(shell);
    let said = folder.run(&format!(
        "$setup = Join-Path $folder 'remoteman-host-setup.exe'
        $trusted = Join-Path $folder 'trusted'
        $encoder = (Get-Content -LiteralPath (Join-Path $folder 'encoder.txt') -Raw).Trim()
        Set-Content -LiteralPath (Join-Path $folder 'installed.txt') -Value ({NOTE_BEFORE}) -Encoding ascii"
    ));
    assert_eq!(said.code, Some(0), "{said}");
    assert!(!folder.installs());
}

#[test]
fn a_device_paired_since_installs_nothing() {
    let Some(shell) = shell() else { return };
    let folder = Folder::new(shell);
    folder.install();
    folder.write("trusted", &format!("{VIEWER} Guesthouse\n{PAIRED} Kitchen tablet\n"));
    assert!(!folder.installs());
}

#[test]
fn another_installer_viewer_or_encoder_installs_again() {
    let Some(shell) = shell() else { return };
    for (name, text) in [
        ("remoteman-host-setup.exe", "remoteman 0.2.0"),
        ("viewer.txt", &format!("{PAIRED} Guesthouse\n")),
        ("encoder.txt", "d3d12"),
    ] {
        let folder = Folder::new(shell);
        folder.install();
        folder.write(name, text);
        assert!(folder.installs(), "{name}");
    }
}

/// The installer replaces the guest's whole list, so it's given the host's merged list, trusted, and
/// never the viewer's line alone.
#[test]
fn the_installer_is_given_the_whole_list() {
    let Some(shell) = shell() else { return };
    let folder = Folder::new(shell);
    let said =
        folder.run("Get-SetupArguments $folder 'auto' 'C:\\setup.log' | ForEach-Object { Write-Output $_ }");
    let trusted = folder.path.join("trusted");
    let expected = [
        "--silent".to_string(),
        "--trust".to_string(),
        format!("\"{}\"", trusted.display()),
        "--encoder".to_string(),
        "auto".to_string(),
        "--no-pair".to_string(),
        "--log".to_string(),
        "\"C:\\setup.log\"".to_string(),
    ];
    assert_eq!(said.lines(), expected, "{said}");
}
