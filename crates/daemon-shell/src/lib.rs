//! The shell around a host's per-machine daemon that is no one host's, so each host's daemon builds
//! on one copy: for now its log lines to standard error, in `logger`.
//!
//! A piece moves here from a host's daemon as it was, and keeps working at its old path there: the
//! Linux daemon's `guesthouse_daemon::logger` is this crate's `logger`.

// Unix only: the logger writes to standard error by its descriptor and reads its log file back where
// it lies. On Windows, which has no daemon of this kind, the crate is empty.
#[cfg(unix)]
pub mod logger;
