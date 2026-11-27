//! What the app asks of Windows itself, beyond the window: the file dialog, the clipboard, Remote
//! Desktop, the icon's file, cancelling a read on the pipe, what opens at sign-in, and the file
//! drop, for a newer Guesthouse. Every `unsafe` call of the app is
//! here, but for the console's, which are in console.rs.

use std::os::windows::io::AsRawHandle;
use std::path::PathBuf;
use std::process::Command;
use std::thread::{self, JoinHandle};

use crate::update;

use windows_sys::Win32::Foundation::{GlobalFree, HWND};
use windows_sys::Win32::System::Com::{
    COINIT_APARTMENTTHREADED, CoInitializeEx, CoTaskMemFree, CoUninitialize,
};
use windows_sys::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData,
};
use windows_sys::Win32::System::IO::CancelSynchronousIo;
use windows_sys::Win32::System::Memory::{GMEM_MOVEABLE, GlobalAlloc, GlobalLock, GlobalUnlock};
use windows_sys::Win32::UI::Controls::Dialogs::{
    GetOpenFileNameW, GetSaveFileNameW, OFN_EXPLORER, OFN_FILEMUSTEXIST, OFN_NOCHANGEDIR,
    OFN_OVERWRITEPROMPT, OFN_PATHMUSTEXIST, OPENFILENAMEW,
};
use windows_sys::Win32::UI::Shell::{
    BIF_NEWDIALOGSTYLE, BIF_RETURNONLYFSDIRS, BROWSEINFOW, SHBrowseForFolderW, SHGetPathFromIDListW,
};

/// The clipboard's format for text in UTF-16.
const UNICODE_TEXT: u32 = 13;
/// The longest path the file dialog gives back, in UTF-16 units: Windows' longest path.
const LONGEST_PATH: usize = 32 * 1024;

/// Ends a read that `thread` is waiting in, if it's in one. The read then fails, as if the pipe had
/// broken.
pub fn cancel_read(thread: &JoinHandle<()>) {
    // SAFETY: the handle is the thread's own, held open by `thread` for the length of the call.
    // Cancelling another thread's synchronous I/O is what the call is for, and only fails when
    // there's nothing to cancel.
    unsafe {
        CancelSynchronousIo(thread.as_raw_handle());
    }
}

/// Puts `text` on the clipboard. `owner` is the window's handle. Returns whether it's there.
pub fn copy(owner: isize, text: &str) -> bool {
    let units: Vec<u16> = text.encode_utf16().chain([0]).collect();
    let bytes = units.len() * size_of::<u16>();
    // SAFETY: the clipboard is opened and closed here, and the memory handed to it is a movable
    // block of `bytes`, filled while locked. Once `SetClipboardData` takes the block it's the
    // system's, so it's freed here only when that fails.
    unsafe {
        if OpenClipboard(owner as HWND) == 0 {
            return false;
        }
        let mut put = false;
        if EmptyClipboard() != 0 {
            let block = GlobalAlloc(GMEM_MOVEABLE, bytes);
            if !block.is_null() {
                let at = GlobalLock(block) as *mut u16;
                if !at.is_null() {
                    std::ptr::copy_nonoverlapping(units.as_ptr(), at, units.len());
                    GlobalUnlock(block);
                    put = !SetClipboardData(UNICODE_TEXT, block).is_null();
                }
                if !put {
                    GlobalFree(block);
                }
            }
        }
        CloseClipboard();
        put
    }
}

/// Windows' file dialog for a machine's image, on a thread of its own, as it runs its own loop of
/// window messages, which mustn't run inside the window's update. `owner` is the window's handle,
/// so the dialog stays in front of it. `chosen` gets the path, or `None` when nothing was chosen.
/// Returns whether the dialog could open.
pub fn pick_image(owner: isize, chosen: impl FnOnce(Option<PathBuf>) + Send + 'static) -> bool {
    thread::Builder::new().name("file dialog".into()).spawn(move || chosen(open_dialog(owner))).is_ok()
}

fn open_dialog(owner: isize) -> Option<PathBuf> {
    let filter: Vec<u16> =
        "Windows or Ubuntu images (*.iso, *.wim, *.esd)\0*.iso;*.wim;*.esd\0All files\0*.*\0\0"
            .encode_utf16()
            .collect();
    let title: Vec<u16> = "Choose the image to make the machine from\0".encode_utf16().collect();
    let mut file = vec![0u16; LONGEST_PATH];
    let mut dialog = OPENFILENAMEW {
        lStructSize: size_of::<OPENFILENAMEW>() as u32,
        hwndOwner: owner as HWND,
        lpstrFilter: filter.as_ptr(),
        nFilterIndex: 1,
        lpstrFile: file.as_mut_ptr(),
        nMaxFile: file.len() as u32,
        lpstrTitle: title.as_ptr(),
        Flags: OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR,
        ..Default::default()
    };
    // SAFETY: COM is started on this thread for the dialog, which needs it for the shell's folders,
    // and ended after it. Every pointer in `dialog` is to a buffer above that outlives the call, the
    // strings end in nulls as the call wants, and `nMaxFile` is the path buffer's length.
    let picked = unsafe {
        let com = CoInitializeEx(std::ptr::null(), COINIT_APARTMENTTHREADED as u32);
        let picked = GetOpenFileNameW(&mut dialog) != 0;
        if com >= 0 {
            CoUninitialize();
        }
        picked
    };
    if !picked {
        return None;
    }
    let end = file.iter().position(|&unit| unit == 0).unwrap_or(file.len());
    Some(PathBuf::from(String::from_utf16_lossy(&file[..end])))
}

/// Windows' Save As dialog for a report, on a thread of its own, as the open dialog is. `name` is the
/// file name it starts with. `chosen` gets the path, or `None` when nothing was chosen. Returns
/// whether the dialog could open.
pub fn pick_save(owner: isize, name: &str, chosen: impl FnOnce(Option<PathBuf>) + Send + 'static) -> bool {
    let name = name.to_owned();
    thread::Builder::new().name("save dialog".into()).spawn(move || chosen(save_dialog(owner, &name))).is_ok()
}

fn save_dialog(owner: isize, name: &str) -> Option<PathBuf> {
    let filter: Vec<u16> =
        "Guesthouse report (*.tar.gz)\0*.tar.gz\0All files\0*.*\0\0".encode_utf16().collect();
    let title: Vec<u16> = "Save the report\0".encode_utf16().collect();
    let extension: Vec<u16> = "gz\0".encode_utf16().collect();
    let mut file = vec![0u16; LONGEST_PATH];
    // The name it starts with, which always fits, as a file's name is far shorter than the buffer.
    for (unit, put) in name.encode_utf16().take(file.len() - 1).zip(file.iter_mut()) {
        *put = unit;
    }
    let mut dialog = OPENFILENAMEW {
        lStructSize: size_of::<OPENFILENAMEW>() as u32,
        hwndOwner: owner as HWND,
        lpstrFilter: filter.as_ptr(),
        nFilterIndex: 1,
        lpstrFile: file.as_mut_ptr(),
        nMaxFile: file.len() as u32,
        lpstrTitle: title.as_ptr(),
        lpstrDefExt: extension.as_ptr(),
        Flags: OFN_EXPLORER | OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR,
        ..Default::default()
    };
    // SAFETY: as in `open_dialog`: COM is started on this thread for the dialog and ended after it,
    // and every pointer in `dialog` is to a buffer above that outlives the call, the strings end in
    // nulls as the call wants, and `nMaxFile` is the path buffer's length.
    let picked = unsafe {
        let com = CoInitializeEx(std::ptr::null(), COINIT_APARTMENTTHREADED as u32);
        let picked = GetSaveFileNameW(&mut dialog) != 0;
        if com >= 0 {
            CoUninitialize();
        }
        picked
    };
    if !picked {
        return None;
    }
    let end = file.iter().position(|&unit| unit == 0).unwrap_or(file.len());
    Some(PathBuf::from(String::from_utf16_lossy(&file[..end])))
}

/// Starts a program with no console window of its own, as the app has none to share.
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Whether this is an installed app, beside the installer's uninstaller. Only an installed app is
/// offered updates: a build of the repo is whatever it was built from.
pub fn installed() -> bool {
    install_folder().is_some()
}

/// The curl Windows has, which needs no library of ours for HTTPS.
fn curl() -> PathBuf {
    let root = std::env::var_os("SystemRoot").unwrap_or_else(|| r"C:\Windows".into());
    PathBuf::from(root).join(r"System32\curl.exe")
}

/// The newest Windows host's file, fetched with the curl Windows has. Only HTTPS, from the file
/// drop's own address with no redirect followed, with a time limit, and no more than the file can be.
fn fetch_latest() -> update::Fetched {
    use std::os::windows::process::CommandExt;
    let limit = guesthouse_control::updates::LONGEST.to_string();
    let output = Command::new(curl())
        .args(["--fail", "--silent", "--globoff", "--proto", "=https", "--max-time", "20"])
        .args(["--max-filesize", &limit, guesthouse_control::updates::LATEST_URL])
        .creation_flags(CREATE_NO_WINDOW)
        .output();
    match output {
        Ok(output) if output.status.success() => {
            update::Fetched::Text(String::from_utf8_lossy(&output.stdout).into_owned())
        }
        _ => update::Fetched::Unreached,
    }
}

/// The updater that reaches the file drop.
pub struct Network;

impl update::Updater for Network {
    fn fetch(&self) -> update::Fetched {
        fetch_latest()
    }
}

/// The install folder, if this is an installed app: the folder above the app's own.
pub fn install_folder() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let folder = exe.parent()?.parent()?;
    folder.join("uninstall.exe").is_file().then(|| folder.to_path_buf())
}

/// Opens the licences of what's installed with Guesthouse, `THIRD-PARTY.md` in the install folder,
/// in Notepad, as Windows may have nothing else for a .md file. A build of the repo has no install
/// folder, so the repo's own file is opened in the browser. Returns words for the person when it
/// couldn't.
pub fn open_licences() -> Result<(), String> {
    let Some(file) =
        install_folder().map(|folder| folder.join("THIRD-PARTY.md")).filter(|file| file.is_file())
    else {
        return open_link(LICENCES_PAGE);
    };
    Command::new("notepad.exe")
        .arg(&file)
        .spawn()
        .map(drop)
        .map_err(|error| format!("Notepad didn't open: {error}. The licences are in {}", file.display()))
}

/// The licences of what Guesthouse is built with, in the repo.
const LICENCES_PAGE: &str = "https://github.com/ruxnlabs/guesthouse/blob/main/THIRD-PARTY.md";

/// Where Windows keeps what opens when this user signs in, and the app's name there.
const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const RUN_NAME: &str = "Guesthouse";

/// What the Run key holds to open this app: its path, in quotes as a path with spaces needs.
fn run_command() -> Option<String> {
    Some(format!("\"{}\"", std::env::current_exe().ok()?.display()))
}

/// Whether this app opens when the person signs in: the Run key names this app's own exe.
pub fn opens_at_sign_in() -> bool {
    use windows_sys::Win32::Foundation::ERROR_SUCCESS;
    use windows_sys::Win32::System::Registry::{HKEY_CURRENT_USER, RRF_RT_REG_SZ, RegGetValueW};
    let (key, name) = (wide(RUN_KEY), wide(RUN_NAME));
    let mut buffer = vec![0u16; LONGEST_PATH];
    let mut bytes = (buffer.len() * size_of::<u16>()) as u32;
    // SAFETY: both names end in a null, and `buffer` holds `bytes` bytes.
    let found = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            key.as_ptr(),
            name.as_ptr(),
            RRF_RT_REG_SZ,
            std::ptr::null_mut(),
            buffer.as_mut_ptr().cast(),
            &mut bytes,
        )
    };
    if found != ERROR_SUCCESS {
        return false;
    }
    let end = buffer.iter().position(|&unit| unit == 0).unwrap_or(buffer.len());
    let held = String::from_utf16_lossy(&buffer[..end]);
    run_command().is_some_and(|command| held.eq_ignore_ascii_case(&command))
}

/// Makes this app open when the person signs in, or not. Returns words for the person when Windows
/// wouldn't.
pub fn set_opens_at_sign_in(on: bool) -> Result<(), String> {
    use windows_sys::Win32::Foundation::{ERROR_FILE_NOT_FOUND, ERROR_SUCCESS};
    use windows_sys::Win32::System::Registry::{
        HKEY_CURRENT_USER, REG_SZ, RegDeleteKeyValueW, RegSetKeyValueW,
    };
    let (key, name) = (wide(RUN_KEY), wide(RUN_NAME));
    let done = if on {
        let command = wide(&run_command().ok_or("The app's own path isn't known.")?);
        // SAFETY: both names end in a null, and the value is `command`'s bytes with its null, as a
        // REG_SZ is kept.
        unsafe {
            RegSetKeyValueW(
                HKEY_CURRENT_USER,
                key.as_ptr(),
                name.as_ptr(),
                REG_SZ,
                command.as_ptr().cast(),
                (command.len() * size_of::<u16>()) as u32,
            )
        }
    } else {
        // SAFETY: both names end in a null.
        match unsafe { RegDeleteKeyValueW(HKEY_CURRENT_USER, key.as_ptr(), name.as_ptr()) } {
            // Not there is off already.
            ERROR_FILE_NOT_FOUND => ERROR_SUCCESS,
            other => other,
        }
    };
    if done == ERROR_SUCCESS {
        Ok(())
    } else {
        Err(format!(
            "Windows didn't keep that (error {done}). Try again, or use Task Manager's Startup apps."
        ))
    }
}

/// A string as Windows' calls take it, with its null.
fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain([0]).collect()
}

/// Opens a web page in the person's browser. Returns words for the person when it couldn't.
pub fn open_link(link: &str) -> Result<(), String> {
    Command::new("explorer.exe")
        .arg(link)
        .spawn()
        .map(drop)
        .map_err(|error| format!("The browser didn't open: {error}. The page is {link}"))
}

/// Opens Windows' folder picker on a thread of its own, as it waits until the person chooses, and
/// hands `chosen` the folder, or `None` if they cancelled. Returns whether the picker opened.
pub fn pick_folder(owner: isize, chosen: impl FnOnce(Option<PathBuf>) + Send + 'static) -> bool {
    thread::Builder::new().name("folder dialog".into()).spawn(move || chosen(folder_dialog(owner))).is_ok()
}

fn folder_dialog(owner: isize) -> Option<PathBuf> {
    let title: Vec<u16> = "Choose the folder the machine shares with this PC\0".encode_utf16().collect();
    let info = BROWSEINFOW {
        hwndOwner: owner as HWND,
        lpszTitle: title.as_ptr(),
        ulFlags: BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE,
        ..Default::default()
    };
    let mut path = vec![0u16; LONGEST_PATH];
    // SAFETY: COM is started on this thread for the picker, which needs it, and ended after it. The
    // title ends in a null and outlives the call. The item list the picker returns is the caller's,
    // freed here once its path is read into a buffer of MAX_PATH units at least, as the call wants.
    let picked = unsafe {
        let com = CoInitializeEx(std::ptr::null(), COINIT_APARTMENTTHREADED as u32);
        let list = SHBrowseForFolderW(&info);
        let picked = !list.is_null() && SHGetPathFromIDListW(list, path.as_mut_ptr()) != 0;
        if !list.is_null() {
            CoTaskMemFree(list.cast());
        }
        if com >= 0 {
            CoUninitialize();
        }
        picked
    };
    if !picked {
        return None;
    }
    let end = path.iter().position(|&unit| unit == 0).unwrap_or(path.len());
    Some(PathBuf::from(String::from_utf16_lossy(&path[..end])))
}

/// A time in seconds since 1970 in UTC as this PC's own clock shows it, such as `2026-11-23 14:05`.
pub fn local_time(seconds: u64) -> String {
    use windows_sys::Win32::Foundation::{FILETIME, SYSTEMTIME};
    use windows_sys::Win32::System::Time::{FileTimeToSystemTime, SystemTimeToTzSpecificLocalTime};
    /// FILETIME counts tenths of a microsecond from 1601.
    const FROM_1601: u64 = 11_644_473_600;
    const TICKS: u64 = 10_000_000;
    let ticks = (seconds + FROM_1601) * TICKS;
    let file = FILETIME { dwLowDateTime: ticks as u32, dwHighDateTime: (ticks >> 32) as u32 };
    let (mut utc, mut local) = (SYSTEMTIME::default(), SYSTEMTIME::default());
    // SAFETY: every pointer is to a value on the stack that outlives the call, and a null time zone
    // is this PC's own.
    let converted = unsafe {
        FileTimeToSystemTime(&file, &mut utc) != 0
            && SystemTimeToTzSpecificLocalTime(std::ptr::null(), &utc, &mut local) != 0
    };
    if !converted {
        return format!("{seconds} s after 1970");
    }
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}",
        local.wYear, local.wMonth, local.wDay, local.wHour, local.wMinute
    )
}

/// Opens Remote Desktop on `address`. Returns words for the person when it couldn't.
pub fn remote_desktop(address: &str) -> Result<(), String> {
    Command::new("mstsc")
        .arg(format!("/v:{address}"))
        .spawn()
        .map(drop)
        .map_err(|error| format!("Remote Desktop didn't open: {error}"))
}

/// The exe's icon, as make-icon.ps1 draws it: a PNG for each size.
const ICON: &[u8] = include_bytes!("../assets/guesthouse.ico");
/// An icon file's header: where it says how many sizes follow, and its length. Each size's entry
/// after it has its width (one byte, as is its height), and where its picture is in the file and
/// how long, as little-endian u32s.
const ICON_COUNT_AT: usize = 4;
const ICON_HEADER: usize = 6;
const ICON_ENTRY: usize = 16;
const ENTRY_WIDTH_AT: usize = 0;
const ENTRY_LENGTH_AT: usize = 8;
const ENTRY_OFFSET_AT: usize = 12;

/// One size of the icon, as a PNG. The small ones are drawn plainer than the SVG, so they stay
/// clear at a title bar's size, and they're the same picture the taskbar shows.
pub fn icon_frame(size: u8) -> Option<&'static [u8]> {
    let field = |at: usize, len: usize| ICON.get(at..at + len);
    let word = |bytes: &[u8], at: usize| -> Option<usize> {
        Some(u32::from_le_bytes(bytes.get(at..at + 4)?.try_into().ok()?) as usize)
    };
    let count = u16::from_le_bytes(field(ICON_COUNT_AT, 2)?.try_into().ok()?) as usize;
    (0..count).find_map(|n| {
        let entry = field(ICON_HEADER + n * ICON_ENTRY, ICON_ENTRY)?;
        if entry[ENTRY_WIDTH_AT] != size {
            return None;
        }
        field(word(entry, ENTRY_OFFSET_AT)?, word(entry, ENTRY_LENGTH_AT)?)
    })
}

/// The window's icon, which WinUI takes as a file: written once into this user's temporary folder,
/// as it's part of the exe and nothing ships beside it.
pub fn icon_file() -> Option<String> {
    let folder = std::env::temp_dir().join("guesthouse-app");
    let path = folder.join("guesthouse.ico");
    if std::fs::read(&path).ok().as_deref() != Some(ICON) {
        std::fs::create_dir_all(&folder).ok()?;
        std::fs::write(&path, ICON).ok()?;
    }
    Some(path.to_string_lossy().into_owned())
}

/// Where a panic is written, as the app has no console.
pub fn panic_file() -> PathBuf {
    std::env::temp_dir().join("guesthouse-app").join("panic.txt")
}
