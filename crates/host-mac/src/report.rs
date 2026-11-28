//! Bug reports: what is gathered about one machine and this Mac, made into one file the person can
//! send to the developer with a click, or save and attach. The Linux and Windows hosts do the
//! same, and the Mac does it with their words and their server.
//!
//! The words, limits, address, summary and sorting are the shared crate's (`guesthouse-control`'s
//! `report`, which has no OS calls), so a report from a Mac is the same on the wire as one from the
//! others. What is the Mac's: where the parts come from (`collect`), what is taken out beyond what
//! the others take out (`extra`), and the folder a report is kept in (`bundle`).
//!
//! Nothing here sends anything unless the app asks, and the app asks only when the person has seen
//! what is in the report and pressed Send.

pub mod bundle;
pub mod cli;
pub mod collect;
pub mod extra;
pub mod send;

pub use guesthouse_control::report::ProblemKind;
use serde::Deserialize;

/// What the person chose and wrote, and what the app knows that the core does not.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct Request {
    /// The machine's folder name, or none for a report about the app.
    pub machine: Option<String>,
    /// The kind of problem, by its word (`wont-start`, `crashed`, `picture`, `slow`,
    /// `install-failed`, `other`).
    pub kind: String,
    pub description: String,
    pub contact: String,
    /// Whether the guest's serial log goes in.
    pub include_serial: bool,
    /// Whether the machine is running now, which decides what the person is told before sending.
    pub machine_running: bool,
    pub app_version: String,
    /// The guest driver's version, when the app knows it.
    pub driver_version: Option<String>,
}

impl Request {
    pub fn problem_kind(&self) -> ProblemKind {
        ProblemKind::from_word(&self.kind).unwrap_or_default()
    }
}

/// What to tell the person before they send, if the report would be thin: no logs of the machine
/// running, or a machine that is not running to ask. As the Linux app says it, and sending anyway
/// is always theirs to choose.
pub fn before_sending(
    machine: bool,
    running: bool,
    has_run_logs: bool,
    kind: ProblemKind,
) -> Option<String> {
    if !machine {
        return None;
    }
    let can_run = !matches!(kind, ProblemKind::WontStart | ProblemKind::InstallFailed);
    let not_running = can_run && !running;
    let text = match (!has_run_logs, not_running) {
        (true, true) => {
            "This report has no logs of the machine running, and logs from inside the guest need it running. \
             The fullest report comes with the machine running: start it, make the problem happen again if \
             you can, then send."
        }
        (true, false) => {
            "This report has no logs of the machine running. Start it, make the problem happen again, then \
             send. If it won't start at all, send anyway."
        }
        (false, true) => {
            "The machine isn't running, so the report has nothing from inside the guest. The fullest report \
             comes with it running: start it, make the problem happen if you can, then send."
        }
        (false, false) => return None,
    };
    Some(text.to_owned())
}

#[cfg(test)]
mod tests;
