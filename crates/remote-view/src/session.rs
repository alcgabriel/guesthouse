//! Pairing driven against a running guest: each machine's [`Session`] (its pairing, its last
//! reading of the host's status and why that failed), and the [`Driver`] that feeds pairing its
//! events, sends the `ctl` commands that come back, and reads the host again when it is asked to.
//!
//! What only a host can do comes in through [`Guest`]: running `ctl` words in the guest, writing
//! its log, and, on a host that can be stopped without a goodbye while pairing holds something
//! off, keeping that where its next run finds it. The clock comes in as a function, and threads,
//! polling and the switch are the host's own.
//!
//! A session is locked only for a moment, never while the guest is asked something, so a screen
//! can always be shown what was last read.

use crate::ctl::{self, Ack, Words, parse_ack};
use crate::pairing::{Event, HostWide, Millis, Pairing};
use crate::policy::Policy;
use crate::share::{ShareInfo, ShareState};
use crate::status::{Reply, Status, parse_reply};
use crate::view::{Facts, share_info};
use std::collections::HashMap;
use std::sync::{Mutex, PoisonError};

/// How old a reading may be before a screen has another taken behind it.
pub const STALE_MS: Millis = 2_000;
/// What is said when a device command finds the guest's host shutting down.
pub const HOST_STOPPING: &str = "remoteman's host is stopping.";

/// What the driver asks of the host it runs on.
pub trait Guest {
    /// Runs one `ctl` command in the guest's remoteman host, and gives what it printed: nothing, if
    /// the guest did not answer.
    fn ctl(&self, words: &Words) -> String;

    /// Writes one line in the host's log.
    fn log(&self, line: &str);

    /// What an earlier run wrote down of [`Pairing::held`]. A host with nowhere to keep it gives
    /// nothing. It is asked with the sessions locked, so it must not touch them.
    fn held(&self) -> Option<HostWide> {
        None
    }

    /// Writes down [`Pairing::held`] after every step, once its commands have gone out, so that a
    /// run that ends with something held off gives it back at the next. A host with nowhere to keep
    /// it does nothing.
    fn keep_held(&self, _held: Option<HostWide>) {}
}

/// What one machine's pairing has, between calls.
#[derive(Debug, Default)]
pub struct Session {
    pub pairing: Option<Pairing>,
    /// The last status the host gave.
    pub reading: Option<Status>,
    /// When the host was last asked for its status.
    pub read_at: Option<Millis>,
    /// Why the last reading failed, in the host's words.
    pub reason: Option<String>,
    /// A reading or a clock is running behind the screen. The host's own: the driver never sets it.
    pub busy: bool,
    /// The host's fingerprint, kept from the last reading that had it.
    pub fingerprint: Option<String>,
}

impl Session {
    /// What a screen shows, from what was last read. `state` and `port` are the host's, and
    /// `reason` is a failure of its own, which goes before a failed reading's.
    pub fn shown(
        &self,
        machine: &str,
        policy: &Policy,
        state: ShareState,
        port: Option<u16>,
        reason: Option<String>,
    ) -> ShareInfo {
        let reason = reason.or(self.reason.clone());
        let pairing = self.pairing.clone().unwrap_or_else(|| Pairing::new(policy.clone()));
        let facts = Facts {
            machine,
            state,
            port,
            fingerprint: self.fingerprint.as_deref(),
            reason: reason.as_deref(),
        };
        share_info(&facts, self.reading.as_ref(), &pairing)
    }

    /// Whether the last reading is old enough at `now` that another should be taken. A clock that
    /// went back counts as old.
    pub fn stale(&self, now: Millis) -> bool {
        self.read_at.is_none_or(|at| now.checked_sub(at).is_none_or(|age| age >= STALE_MS))
    }
}

/// Every machine's session, by the machine's name.
#[derive(Debug, Default)]
pub struct Sessions {
    all: Mutex<HashMap<String, Session>>,
}

impl Sessions {
    /// Runs `change` on the machine's session, made empty if it has none, with every session
    /// locked. Never ask the guest from inside it.
    pub fn with<R>(&self, machine: &str, change: impl FnOnce(&mut Session) -> R) -> R {
        let mut all = self.all.lock().unwrap_or_else(PoisonError::into_inner);
        change(all.entry(machine.to_string()).or_default())
    }

    /// Forgets the machine's session.
    pub fn remove(&self, machine: &str) {
        self.all.lock().unwrap_or_else(PoisonError::into_inner).remove(machine);
    }

    /// The machines that have a session.
    pub fn machines(&self) -> Vec<String> {
        self.all.lock().unwrap_or_else(PoisonError::into_inner).keys().cloned().collect()
    }
}

/// What a step is fed.
#[derive(Debug, Clone, Copy)]
pub enum StepEvent {
    Plain(Event<'static>),
    /// Read the host's status, and feed the reading in.
    Read,
}

/// A pairing for this run of the host: whatever an earlier run held is owed back.
pub fn fresh_pairing(policy: Policy, held: Option<HostWide>) -> Pairing {
    Pairing::new(policy).step(0, Event::Started { held }).pairing
}

/// One machine's pairing, as one call drives it.
pub struct Driver<'a> {
    pub sessions: &'a Sessions,
    pub machine: &'a str,
    pub policy: &'a Policy,
    pub guest: &'a dyn Guest,
    /// Milliseconds since 1970, read before each step and each reading.
    pub now: &'a dyn Fn() -> Millis,
}

impl Driver<'_> {
    /// A pairing for this run, from what the guest's host kept of an earlier one.
    pub fn fresh_pairing(&self) -> Pairing {
        fresh_pairing(self.policy.clone(), self.guest.held())
    }

    /// Feeds one event to the machine's pairing, sends the commands it gives in order, keeps
    /// `held`, and reads the host again when asked to. Gives why the event was refused.
    pub fn step(&self, event: StepEvent) -> Option<String> {
        let mut pairing = self.sessions.with(self.machine, |session| {
            session.pairing.get_or_insert_with(|| self.fresh_pairing()).clone()
        });
        let mut events = vec![event];
        let mut refused = None;
        while let Some(event) = events.pop() {
            let reading;
            let step = match &event {
                StepEvent::Plain(event) => pairing.step((self.now)(), *event),
                StepEvent::Read => {
                    reading = self.read();
                    let Some(status) = &reading else { continue };
                    pairing.step((self.now)(), Event::Reading(status))
                }
            };
            pairing = step.pairing;
            refused = refused.or(step.refused);
            for words in &step.commands {
                let said = self.guest.ctl(words);
                if let Ack::Refused(why) = parse_ack(&said) {
                    self.guest.log(&format!("ctl {}: {why}", words.join(" ")));
                }
            }
            self.guest.keep_held(pairing.held());
            if step.read_now || !step.commands.is_empty() {
                events.push(StepEvent::Read);
            }
        }
        self.sessions.with(self.machine, |session| session.pairing = Some(pairing));
        refused
    }

    /// Reads the host's status, and keeps it.
    pub fn read(&self) -> Option<Status> {
        let said = self.guest.ctl(&ctl::status());
        let now = (self.now)();
        self.sessions.with(self.machine, |session| {
            session.read_at = Some(now);
            match parse_reply(&said) {
                Reply::Status(status) => {
                    session.reason = None;
                    session.fingerprint = status.fingerprint.clone().or(session.fingerprint.take());
                    session.reading = Some(*status.clone());
                    Some(*status)
                }
                Reply::Stopping => None,
                Reply::Error(why) => {
                    session.reason = Some(why);
                    None
                }
            }
        })
    }

    /// Opens pairing for `seconds`, once the host has been read, as it has to have been. Gives why
    /// it did not open.
    pub fn open_pairing(&self, seconds: u64) -> Option<String> {
        self.step(StepEvent::Read);
        self.step(StepEvent::Plain(Event::Open { seconds }))
    }

    /// Sends one command about a device, then reads the host again. Gives why the host would not.
    pub fn device(&self, words: &Words) -> Result<(), String> {
        match parse_ack(&self.guest.ctl(words)) {
            Ack::Done(_) | Ack::NotKept(_) => {}
            Ack::Refused(why) => return Err(why),
            Ack::Stopping => return Err(HOST_STOPPING.to_string()),
        }
        self.read();
        Ok(())
    }

    /// The host found the machine running at its start: whatever pairing an earlier run left open
    /// is closed and what it held is given back.
    pub fn started(&self) {
        let fresh = self.fresh_pairing();
        self.sessions.with(self.machine, |session| session.pairing = Some(fresh));
        self.step(StepEvent::Read);
    }

    /// How soon to read again, while pairing is open or a device waits.
    pub fn poll_ms(&self) -> Option<Millis> {
        let all = self.sessions.all.lock().unwrap_or_else(PoisonError::into_inner);
        all.get(self.machine).and_then(|session| session.pairing.as_ref()).and_then(Pairing::poll_ms)
    }
}

#[cfg(test)]
mod tests;
