//! The C functions for finding QEMU and for adding and renaming machines. Like the rest of the
//! interface, they take and give JSON text, and every string they return is freed with
//! `guesthouse_string_free`.

use crate::create::{self, NewMachine};
use crate::store;
use crate::tools::{self, Places, Tool};
use crate::{error_json, into_c_string};
use serde_json::json;
use std::ffi::{CStr, c_char};
use std::path::PathBuf;

/// A C string as text, or `None` for null or not UTF-8.
///
/// # Safety
/// `text` is null or points to a nul-terminated string.
unsafe fn text<'a>(text: *const c_char) -> Option<&'a str> {
    if text.is_null() {
        return None;
    }
    // SAFETY: the caller promises a nul-terminated string.
    unsafe { CStr::from_ptr(text) }.to_str().ok()
}

/// Finds the program `tool` ("qemu", "rmhost", "pvg-host" or "pvg-qemu") to run. `setting` is what Settings holds (null or
/// empty for nothing) and `bundled` where the app bundle keeps its own copy (null for none). Returns
/// `{"path", "source", "why"}`, with `source` one of `setting`, `environment`, `bundled` or
/// `lab`, or `{"error": "..."}` with a sentence saying what is missing.
///
/// # Safety
/// All are null or point to nul-terminated strings.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_tool_locate(
    tool: *const c_char,
    setting: *const c_char,
    bundled: *const c_char,
) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let (tool, setting, bundled) = unsafe { (text(tool), text(setting), text(bundled)) };
    let tool = match tool {
        Some("qemu") => Tool::Qemu,
        Some("rmhost") => Tool::Rmhost,
        Some("pvg-host") => Tool::PvgHost,
        Some("pvg-qemu") => Tool::PvgQemu,
        _ => {
            return into_c_string(error_json(
                "the tool is not qemu, rmhost, pvg-host or pvg-qemu",
            ));
        }
    };
    let places = Places::on_this_mac(tool, setting.map(String::from), bundled.map(PathBuf::from));
    into_c_string(match tools::locate_checked(tool, &places) {
        Ok(found) => json!({
            "path": found.path.display().to_string(),
            "source": found.source.name(),
            "why": found.why,
        })
        .to_string(),
        Err(error) => error_json(&error),
    })
}

/// Checks a new machine, given as JSON (see `create::NewMachine`). Returns
/// `{"problems": [...]}`, empty when it can be made.
///
/// # Safety
/// `request` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_machine_check(request: *const c_char) -> *mut c_char {
    // SAFETY: passed on from the caller.
    into_c_string(match unsafe { read_request(request) } {
        Ok((machines, request)) => {
            json!({ "problems": create::problems(&machines, &request) }).to_string()
        }
        Err(error) => error_json(&error),
    })
}

/// Makes a new machine from JSON as for `guesthouse_machine_check`. Returns `{"id": "..."}`, or
/// `{"problems": [...]}` and nothing made. Copying a large disk takes a while when it cannot be
/// cloned, so call it off the main thread.
///
/// # Safety
/// `request` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_machine_create(request: *const c_char) -> *mut c_char {
    // SAFETY: passed on from the caller.
    into_c_string(match unsafe { read_request(request) } {
        Ok((machines, request)) => match create::create(&machines, &request) {
            Ok(id) => json!({ "id": id }).to_string(),
            Err(problems) => json!({ "problems": problems }).to_string(),
        },
        Err(error) => error_json(&error),
    })
}

/// Renames machine `id` (its folder's name). Returns `{"ok": true}` or `{"error": "..."}`.
///
/// # Safety
/// Both point to nul-terminated strings, or are null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_machine_rename(
    id: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let (id, name) = unsafe { (text(id), text(name)) };
    into_c_string(match (store::default_folder(), id, name) {
        (Some(machines), Some(id), Some(name)) => match create::rename(&machines, id, name) {
            Ok(()) => json!({ "ok": true }).to_string(),
            Err(error) => error_json(&error),
        },
        _ => error_json("no machines folder, or the machine or name is not text"),
    })
}

/// # Safety
/// `request` is null or points to a nul-terminated string.
unsafe fn read_request(request: *const c_char) -> Result<(PathBuf, NewMachine), String> {
    let machines = store::default_folder().ok_or("no machines folder: HOME is not set")?;
    // SAFETY: passed on from the caller.
    let request = unsafe { text(request) }.ok_or("the request is not text")?;
    let request =
        serde_json::from_str(request).map_err(|e| format!("the request is not valid: {e}"))?;
    Ok((machines, request))
}

/// Allows or forbids viewing machine `id`'s screen from other devices, choosing a port the first
/// time it is allowed. Returns `{"port": N}` (null when never allowed) or `{"error": "..."}`.
/// Nothing listens because of this alone: the agent shares the screen of a running machine.
///
/// # Safety
/// `id` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_machine_set_remote_view(
    id: *const c_char,
    on: bool,
) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let id = unsafe { text(id) };
    into_c_string(match (store::default_folder(), id) {
        (Some(machines), Some(id)) => match crate::remote::set_enabled(&machines, id, on) {
            Ok(port) => json!({ "port": port }).to_string(),
            Err(error) => error_json(&error),
        },
        _ => error_json("no machines folder, or the machine is not text"),
    })
}

/// Changes a stopped machine's processors and memory. `request` is JSON with `cores`,
/// `memory_mb`, `host_cores` and `host_memory_mb`. Returns `{"ok": true}` or
/// `{"problems": [...]}`.
///
/// # Safety
/// Both are null or point to nul-terminated strings.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_machine_set_hardware(
    id: *const c_char,
    request: *const c_char,
) -> *mut c_char {
    #[derive(serde::Deserialize)]
    struct Hardware {
        cores: u32,
        memory_mb: u64,
        host_cores: u32,
        host_memory_mb: u64,
    }
    // SAFETY: passed on from the caller.
    let (id, request) = unsafe { (text(id), text(request)) };
    let parsed = request.and_then(|text| serde_json::from_str::<Hardware>(text).ok());
    into_c_string(match (store::default_folder(), id, parsed) {
        (Some(machines), Some(id), Some(h)) => {
            match create::set_hardware(
                &machines,
                id,
                h.cores,
                h.memory_mb,
                h.host_cores,
                h.host_memory_mb,
            ) {
                Ok(()) => json!({ "ok": true }).to_string(),
                Err(problems) => json!({ "problems": problems }).to_string(),
            }
        }
        _ => error_json("no machines folder, or the request is not valid"),
    })
}

/// Sets where machine `id`'s graphics device lives, `guarded` or `qemu`. Returns `{"ok": true}`
/// or `{"error": "..."}`.
///
/// # Safety
/// Both are null or point to nul-terminated strings.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_machine_set_graphics(
    id: *const c_char,
    graphics: *const c_char,
) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let (id, graphics) = unsafe { (text(id), text(graphics)) };
    into_c_string(match (store::default_folder(), id, graphics) {
        (Some(machines), Some(id), Some(graphics)) => {
            match create::set_graphics(&machines, id, graphics) {
                Ok(()) => json!({ "ok": true }).to_string(),
                Err(error) => error_json(&error),
            }
        }
        _ => error_json("no machines folder, or the machine or choice is not text"),
    })
}

/// Records the size machine `id`'s screen should be so that it fills its window: the pixels and
/// the scaling (100 or 200). Today this only records it; nothing tells the guest yet. Returns
/// `{"ok": true, "applied": false}` or `{"error": "..."}`.
///
/// # Safety
/// `id` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_machine_set_wanted_screen(
    id: *const c_char,
    width_px: u32,
    height_px: u32,
    scaling_percent: u32,
) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let id = unsafe { text(id) };
    into_c_string(match id {
        Some(id) => {
            let wanted = crate::screen_size::Wanted {
                width_px,
                height_px,
                scaling_percent,
            };
            match crate::screen_size::record(id, wanted) {
                Ok(()) => json!({ "ok": true, "applied": false }).to_string(),
                Err(error) => error_json(&error),
            }
        }
        None => error_json("the machine is not text"),
    })
}

/// Asks machine `id`'s graphics process how it is doing, over its control socket. Returns the
/// numbers of its `status` line as JSON (`published`, `skipped`, `dropped`, `failed`,
/// `refused`, `frames`, and so on, plus `picture` as "WxH"), or `{"error": "..."}` when the
/// machine has no graphics process running. One short connection; never waits long.
///
/// # Safety
/// `id` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_graphics_status(id: *const c_char) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let id = unsafe { text(id) };
    into_c_string(match (store::default_folder(), id) {
        (Some(machines), Some(id)) => {
            match crate::probe::graphics_status(
                &store::run_folder(&machines, id).join("control.sock"),
            ) {
                Ok(numbers) => numbers.to_string(),
                Err(error) => error_json(&error),
            }
        }
        _ => error_json("no machines folder, or the machine is not text"),
    })
}

/// Looks once for a newer Mac release of Guesthouse, with `current` the running version. Returns
/// `{"state": "newer", "version", "where"}`, `{"state": "latest"}` or `{"state": "cant_tell"}`.
/// Waits for the network (at most twenty seconds), so call it off the main thread. Downloads and
/// installs nothing.
///
/// # Safety
/// `current` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_update_check(current: *const c_char) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let current = unsafe { text(current) };
    into_c_string(match current {
        Some(current) => crate::updates::check(current),
        None => error_json("the version is not text"),
    })
}

/// Whether machine `id`'s graphics driver is the released one: `{"state": "unknown"}` (nothing
/// known, so nothing to say), `current`, `{"state": "old", "reported", "released"}` or
/// `{"state": "missing", "released"}`.
///
/// # Safety
/// `id` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_driver_state(id: *const c_char) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let id = unsafe { text(id) };
    into_c_string(
        match (store::support_folder(), store::default_folder(), id) {
            (Some(support), Some(machines), Some(id))
                if !id.contains('/') && !id.starts_with('.') =>
            {
                crate::driver_version::answer(&crate::driver_version::state(
                    &support,
                    &machines.join(id),
                ))
            }
            _ => json!({"state": "unknown"}).to_string(),
        },
    )
}

/// Keeps the version of the graphics driver machine `id` reported, for the comparison above.
/// `{"ok": true}` or `{"error": "..."}`.
///
/// # Safety
/// Both are null or point to nul-terminated strings.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_driver_record(
    id: *const c_char,
    version: *const c_char,
) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let (id, version) = unsafe { (text(id), text(version)) };
    into_c_string(match (store::default_folder(), id, version) {
        (Some(machines), Some(id), Some(version)) if !id.contains('/') && !id.starts_with('.') => {
            match crate::driver_version::record_reported(&machines.join(id), version) {
                Ok(()) => json!({"ok": true}).to_string(),
                Err(error) => error_json(&error),
            }
        }
        _ => error_json("no machines folder, or the machine or version is not text"),
    })
}

/// Judges one check before a start or a new machine, from facts the app read: `request` is JSON
/// with `"check"` one of `memory`, `memory_now`, `disk` or `advice` and that check's numbers (see
/// `start_checks`). Returns `{"problem": null | {...}}` (title, message and the numbers and flags
/// the buttons need), `{"warning": null | "..."}` for `advice`, or `{"error": "..."}`.
///
/// # Safety
/// `request` is null or points to a nul-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn guesthouse_start_check(request: *const c_char) -> *mut c_char {
    // SAFETY: passed on from the caller.
    let request = unsafe { text(request) };
    into_c_string(match request {
        Some(request) => crate::start_checks::answer(request),
        None => error_json("the check is not text"),
    })
}
