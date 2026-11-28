//! What can stop a machine starting on this Mac, judged from facts handed in: memory against what
//! other machines hold and what is free now, and disk against what the machine's disk can still
//! grow by. No OS calls here: the app reads the Mac's memory and free space and passes them in, and
//! only shows what comes back (a title, a sentence, and the numbers and flags for the buttons).
//!
//! The shape is the other hosts' `start_checks` (facts in, words out); the wording is the
//! design's "When something is wrong" messages. Each answer carries a stable `key` so a host can
//! put its own wording on it later.

use serde::Deserialize;
use serde_json::{Value, json};

/// What the Mac keeps for itself when machines run, so a second machine leaves it this much.
pub const TIGHT_LEFTOVER_MB: i64 = 4096;
/// What the Mac keeps free when a machine starts (against what is free now).
pub const HEADROOM_MB: i64 = 1024;
/// Margin on top of what a disk can still grow by.
const DISK_MARGIN_BYTES: i64 = 2_000_000_000;
const BYTES_PER_GB: i64 = 1_000_000_000;

#[derive(Debug, Deserialize)]
#[serde(tag = "check", rename_all = "snake_case")]
pub enum Check {
    /// Starting `machine` while others run: against the host's memory less theirs and the Mac's own.
    Memory {
        machine: String,
        wanted_mb: i64,
        host_mb: i64,
        #[serde(default)]
        running: Vec<Running>,
    },
    /// Against what is free now. `available_mb` is none when the Mac would not say.
    MemoryNow {
        machine: String,
        wanted_mb: i64,
        available_mb: Option<i64>,
        #[serde(default)]
        running_mb: i64,
    },
    /// The disk can grow from `on_disk_bytes` to `size_bytes`; `free_bytes` is what the Mac has.
    Disk {
        machine: String,
        size_bytes: i64,
        on_disk_bytes: i64,
        free_bytes: i64,
    },
    /// What to say when creating a machine next to ones that run (a warning, not a stop).
    Advice {
        new_mb: i64,
        running_mb: i64,
        host_mb: i64,
    },
}

#[derive(Debug, Deserialize)]
pub struct Running {
    pub name: String,
    pub memory_mb: i64,
}

/// Memory as a person reads it: whole gigabytes, or one decimal.
pub fn memory_words(mb: i64) -> String {
    let gb = mb as f64 / 1024.0;
    if (gb - gb.round()).abs() < 0.05 {
        format!("{} GB", gb.round() as i64)
    } else {
        format!("{gb:.1} GB")
    }
}

fn spare_mb(host_mb: i64, running_mb: i64) -> i64 {
    (host_mb - running_mb - TIGHT_LEFTOVER_MB).max(0)
}

fn memory_problem(
    machine: &str,
    wanted_mb: i64,
    spare: i64,
    running: Option<&str>,
    running_mb: i64,
    start_anyway: bool,
) -> Value {
    let message = match running {
        Some(other) => format!(
            "{machine} is set to {} and this Mac has {} to spare, because {other} is running with {}. Shut {other} down, or give {machine} less.",
            memory_words(wanted_mb),
            memory_words(spare),
            memory_words(running_mb)
        ),
        None => format!(
            "{machine} is set to {} and this Mac has {} to spare. Give {machine} less.",
            memory_words(wanted_mb),
            memory_words(spare)
        ),
    };
    json!({"problem": {
        "key": "not_enough_memory", "kind": "not_enough_memory", "machine": machine,
        "title": format!("Not enough memory to start {machine}"), "message": message,
        "wanted_mb": wanted_mb, "spare_mb": spare, "running": running, "running_mb": running_mb,
        "start_anyway": start_anyway,
    }})
}

/// Judges one check, as JSON: `{"problem": null}` or `{"problem": {...}}`; for `advice`,
/// `{"warning": null | "..."}`.
pub fn judge(check: &Check) -> Value {
    match check {
        Check::Memory {
            machine,
            wanted_mb,
            host_mb,
            running,
        } => {
            let running_mb: i64 = running.iter().map(|r| r.memory_mb).sum();
            // Alone, the core's own limit is the one that matters.
            if running_mb <= 0 {
                return json!({"problem": null});
            }
            let spare = spare_mb(*host_mb, running_mb);
            if *wanted_mb <= spare {
                return json!({"problem": null});
            }
            let name = (running.len() == 1).then(|| running[0].name.as_str());
            memory_problem(machine, *wanted_mb, spare, name, running_mb, false)
        }
        Check::MemoryNow {
            machine,
            wanted_mb,
            available_mb,
            running_mb,
        } => {
            let Some(available) = available_mb else {
                return json!({"problem": null});
            };
            let spare = (available - HEADROOM_MB).max(0);
            if *wanted_mb <= spare {
                return json!({"problem": null});
            }
            memory_problem(machine, *wanted_mb, spare, None, *running_mb, true)
        }
        Check::Disk {
            machine,
            size_bytes,
            on_disk_bytes,
            free_bytes,
        } => {
            let needed = (size_bytes - on_disk_bytes).max(0) + DISK_MARGIN_BYTES;
            if *free_bytes >= needed {
                return json!({"problem": null});
            }
            let needed_gb = (needed + BYTES_PER_GB - 1) / BYTES_PER_GB;
            let free_gb = free_bytes / BYTES_PER_GB;
            json!({"problem": {
                "key": "not_enough_disk", "kind": "not_enough_disk", "machine": machine,
                "title": format!("Not enough disk space to start {machine}"),
                "message": format!("{machine}'s disk can grow by up to {needed_gb} GB and this Mac has {free_gb} GB free. Free some space on this Mac, or move machines you do not need to the Trash."),
                "needed_gb": needed_gb, "free_gb": free_gb,
            }})
        }
        Check::Advice {
            new_mb,
            running_mb,
            host_mb,
        } => {
            if *running_mb <= 0 {
                return json!({"warning": null});
            }
            let left = host_mb - running_mb - new_mb;
            if left > TIGHT_LEFTOVER_MB {
                return json!({"warning": null});
            }
            json!({"warning": format!(
                "Another machine is running with {}. Starting both would leave this Mac {}. You can still create this one and start it later.",
                memory_words(*running_mb), memory_words(left.max(0)))})
        }
    }
}

/// From the app's JSON request to the answer's.
pub fn answer(request: &str) -> String {
    match serde_json::from_str::<Check>(request) {
        Ok(check) => judge(&check).to_string(),
        Err(error) => json!({"error": format!("the check is not valid: {error}")}).to_string(),
    }
}

#[cfg(test)]
mod tests;
