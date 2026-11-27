//! Bug reports for a Windows host. The Windows app builds a report with these, and sends it to the
//! same server the Linux host's reports go to, so what's on the wire is the same. The service only
//! hands over its files. It never builds or sends a report.
//!
//! - `contract` is what the server and every host agree on, from `guesthouse-report-core`.
//! - `answer` reads the server's answer to a sent report.
//! - `kind` and `summary` are what sorts a report before anyone opens it.
//! - `parts` is how the service's files come over the pipe, and are put back together.
//! - `stage` makes the files from what was gathered, `send` is how they are posted, and `issue` is
//!   the link that opens an issue about a sent report.
//! - `clock` writes times in UTC, from `guesthouse-report-core`.
//! - `scrub` and `trim` make each file fit to send, and `manifest` says what the bundle holds.
//!
//! Nothing here calls into Windows, so it builds and is tested anywhere.

pub mod issue;
pub mod parts;
pub mod scrub;
pub mod stage;

// The pieces every host shares, under the names they had here.
pub use guesthouse_report_core::{answer, clock, contract, kind, manifest, send, summary, trim};

pub use answer::read_answer;
pub use contract::{KEPT_DAYS, MOST_REPORT_BYTES, NEW_ISSUE, report_address};
pub use issue::issue_link;
pub use kind::ProblemKind;
pub use manifest::{MANIFEST_FILE, manifest};
pub use parts::{PIECE_BYTES, Parts, pieces};
pub use scrub::Scrubber;
pub use summary::Summary;
pub use trim::keep_end;
