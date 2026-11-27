//! Whether a newer Windows host is out, as the app's Settings page shows it, and the yellow dot on
//! its Settings button. This is the plain logic: what each thing that happens changes, and what's
//! to be done next, with nothing of Windows or the network in it, so its tests run on any system.
//! The app does what it's told to through an [`Updater`]; the real one is in system.rs, and a fake
//! one for the tests and the preview is below.
//!
//! What the file drop's file says to this version is decided in `guesthouse_control::updates`, on
//! the check every host shares (`guesthouse-update-check`): newer, the newest, or can't tell.

// Off Windows only the tests use these.
#![cfg_attr(not(windows), allow(dead_code))]

use guesthouse_control::updates::{self, Latest};

/// Why a look didn't say.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum CantTell {
    /// The file drop couldn't be reached: no network, or it didn't answer in time.
    Unreached,
    /// It answered with something that isn't a file a release writes.
    Garbled,
}

impl CantTell {
    /// What the person is told, which says what to do.
    pub fn words(&self) -> &'static str {
        match self {
            CantTell::Unreached => {
                "files.ruxn.com couldn't be reached. Check this PC's network, then look again."
            }
            CantTell::Garbled => {
                "files.ruxn.com answered with something that isn't a release's file. Look again later."
            }
        }
    }
}

/// Where the looking stands.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Phase {
    /// A build of the repo, which is whatever it was built from, and never looks.
    NotInstalled,
    /// Not looked yet since the app started.
    NotLooked,
    Looking,
    /// This is the newest, as the file said at `looked`, in seconds since 1970.
    Newest {
        looked: u64,
    },
    /// A newer one is out.
    Newer {
        latest: Latest,
        looked: u64,
    },
    CantTell {
        why: CantTell,
        looked: u64,
    },
}

/// What a fetch of the latest file came back with.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Fetched {
    Text(String),
    Unreached,
}

/// What happened, which the app hands to [`Updates::step`].
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Input {
    /// Look now, as the person asked, or as the app does by itself.
    Look,
    /// The fetch started as `attempt` came back.
    Looked { attempt: u64, fetched: Fetched },
    /// Put the newer one aside until the app next starts: the dot goes, the page still says.
    PutAside,
}

/// What the app is to do next, for the step that asked.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Effect {
    /// Fetch the latest file, and hand back what came as `Input::Looked` with this attempt.
    Fetch { attempt: u64 },
}

/// The updates' state.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Updates {
    pub phase: Phase,
    /// Counts each fetch, so an answer to one that's been overtaken changes nothing.
    attempt: u64,
    /// The newer one was put aside, so the dot doesn't show.
    pub put_aside: bool,
    /// This app's version.
    current: String,
}

impl Updates {
    /// An installed app of version `current`, or a build of the repo when not `installed`.
    pub fn new(installed: bool, current: &str) -> Updates {
        Updates {
            phase: if installed { Phase::NotLooked } else { Phase::NotInstalled },
            attempt: 0,
            put_aside: false,
            current: current.to_owned(),
        }
    }

    /// Takes in what happened at `now`, in seconds since 1970, and says what's to be done next.
    pub fn step(&mut self, input: Input, now: u64) -> Vec<Effect> {
        match input {
            Input::Look => {
                if matches!(self.phase, Phase::NotInstalled | Phase::Looking) {
                    return Vec::new();
                }
                self.attempt += 1;
                self.phase = Phase::Looking;
                vec![Effect::Fetch { attempt: self.attempt }]
            }
            Input::Looked { attempt, fetched } => {
                if attempt != self.attempt || self.phase != Phase::Looking {
                    return Vec::new();
                }
                self.phase = self.judge(fetched, now);
                Vec::new()
            }
            Input::PutAside => {
                self.put_aside = true;
                Vec::new()
            }
        }
    }

    /// What a fetch's answer says to this version.
    fn judge(&self, fetched: Fetched, now: u64) -> Phase {
        let text = match fetched {
            Fetched::Text(text) => text,
            Fetched::Unreached => return Phase::CantTell { why: CantTell::Unreached, looked: now },
        };
        match updates::parse(&text) {
            Some(latest) if updates::newer(&latest.version, &self.current) => {
                Phase::Newer { latest, looked: now }
            }
            Some(_) => Phase::Newest { looked: now },
            None => Phase::CantTell { why: CantTell::Garbled, looked: now },
        }
    }

    /// Whether a look can be asked for now: an installed app that isn't looking already.
    pub fn can_look(&self) -> bool {
        !matches!(self.phase, Phase::NotInstalled | Phase::Looking)
    }

    /// The newer one, if one is out.
    pub fn newer(&self) -> Option<&Latest> {
        match &self.phase {
            Phase::Newer { latest, .. } => Some(latest),
            _ => None,
        }
    }

    /// Whether the Settings button has its dot: a newer one is out, and wasn't put aside.
    pub fn dot(&self) -> bool {
        self.newer().is_some() && !self.put_aside
    }
}

/// What the app asks of the network and of Windows for an update. The real one is in system.rs,
/// and [`Fake`] stands in for it in the tests and the preview.
pub trait Updater: Send + Sync {
    /// Fetches the latest file from the file drop.
    fn fetch(&self) -> Fetched;
}

/// An updater that answers as it's told to, at once, and touches nothing.
#[cfg(any(test, feature = "preview"))]
pub struct Fake {
    pub fetched: Fetched,
}

#[cfg(any(test, feature = "preview"))]
impl Updater for Fake {
    fn fetch(&self) -> Fetched {
        self.fetched.clone()
    }
}

/// A latest file as a release writes it, for `version`, for the tests and the preview.
#[cfg(any(test, feature = "preview"))]
pub fn release_file(version: &str) -> String {
    format!(
        r#"{{"version": "{version}", "installer": "https://files.ruxn.com/p/guesthouse/guesthouse-setup-{version}.exe", "sha256": "{}", "notes": "https://github.com/ruxnlabs/guesthouse/releases/tag/windows-v{version}"}}"#,
        "ab".repeat(32)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: u64 = 1_795_000_000;

    fn looking() -> (Updates, u64) {
        let mut updates = Updates::new(true, "0.13.0");
        let effects = updates.step(Input::Look, NOW);
        let [Effect::Fetch { attempt }] = effects[..] else { panic!("{effects:?}") };
        (updates, attempt)
    }

    fn text(version: &str) -> Fetched {
        Fetched::Text(release_file(version))
    }

    #[test]
    fn a_build_of_the_repo_never_looks() {
        let mut updates = Updates::new(false, "0.13.0");
        assert_eq!(updates.phase, Phase::NotInstalled);
        assert!(updates.step(Input::Look, NOW).is_empty());
        assert_eq!(updates.phase, Phase::NotInstalled);
        assert!(!updates.can_look());
        assert!(!updates.dot());
    }

    #[test]
    fn a_look_says_newer_newest_or_cant_tell() {
        let (mut updates, attempt) = looking();
        assert_eq!(updates.phase, Phase::Looking);
        assert!(!updates.can_look(), "one look at a time");
        updates.step(Input::Looked { attempt, fetched: text("0.14.0") }, NOW + 1);
        assert!(
            matches!(&updates.phase, Phase::Newer { latest, looked } if latest.version == "0.14.0" && *looked == NOW + 1)
        );
        assert!(updates.dot());

        let (mut updates, attempt) = looking();
        updates.step(Input::Looked { attempt, fetched: text("0.13.0") }, NOW);
        assert_eq!(updates.phase, Phase::Newest { looked: NOW });
        assert!(!updates.dot());

        let (mut updates, attempt) = looking();
        updates.step(Input::Looked { attempt, fetched: text("0.9.0") }, NOW);
        assert_eq!(updates.phase, Phase::Newest { looked: NOW }, "an older file isn't newer");

        let (mut updates, attempt) = looking();
        updates.step(Input::Looked { attempt, fetched: Fetched::Unreached }, NOW);
        assert_eq!(updates.phase, Phase::CantTell { why: CantTell::Unreached, looked: NOW });
        assert!(updates.can_look(), "and it can look again");

        let (mut updates, attempt) = looking();
        updates.step(Input::Looked { attempt, fetched: Fetched::Text("<html>".to_owned()) }, NOW);
        assert_eq!(updates.phase, Phase::CantTell { why: CantTell::Garbled, looked: NOW });
    }

    #[test]
    fn an_installer_that_isnt_on_the_file_drop_is_never_offered() {
        let (mut updates, attempt) = looking();
        let file = release_file("0.14.0").replace("files.ruxn.com", "example.com");
        updates.step(Input::Looked { attempt, fetched: Fetched::Text(file) }, NOW);
        assert_eq!(updates.phase, Phase::CantTell { why: CantTell::Garbled, looked: NOW });
    }

    #[test]
    fn a_second_look_while_one_goes_on_starts_nothing_and_an_old_answer_changes_nothing() {
        let (mut updates, attempt) = looking();
        assert!(updates.step(Input::Look, NOW).is_empty());
        updates.step(Input::Looked { attempt: attempt + 7, fetched: text("0.14.0") }, NOW);
        assert_eq!(updates.phase, Phase::Looking, "an answer to no fetch of this one's");
        updates.step(Input::Looked { attempt, fetched: text("0.13.0") }, NOW);
        assert_eq!(updates.phase, Phase::Newest { looked: NOW });
        // The same answer again, late, is for a look that has ended.
        updates.step(Input::Looked { attempt, fetched: text("0.14.0") }, NOW);
        assert_eq!(updates.phase, Phase::Newest { looked: NOW });
    }

    #[test]
    fn put_aside_hides_the_dot_and_a_look_after_keeps_it_hidden() {
        let (mut updates, attempt) = looking();
        updates.step(Input::Looked { attempt, fetched: text("0.14.0") }, NOW);
        updates.step(Input::PutAside, NOW);
        assert!(!updates.dot());
        assert!(updates.newer().is_some(), "the page still says it's out");
        let [Effect::Fetch { attempt }] = updates.step(Input::Look, NOW)[..] else { panic!() };
        updates.step(Input::Looked { attempt, fetched: text("0.14.0") }, NOW);
        assert!(!updates.dot(), "until the app next starts");
    }

    #[test]
    fn the_fake_answers_as_told() {
        let fake = Fake { fetched: Fetched::Unreached };
        assert_eq!(fake.fetch(), Fetched::Unreached);
    }
}
