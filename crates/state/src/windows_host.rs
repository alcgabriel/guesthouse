//! The Windows host's machine states. They go over the service's pipe by these names, lower case,
//! inside an event as `{"kind": "state", "text": NAME}`, and an app reads no other: a new name
//! would reach an old app as one it can't read. The service and the app say them in words of
//! their own, which differ, and both are kept.

use serde::{Deserialize, Serialize};

/// Where a machine stands, as the service tells the app.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Preparing,
    Starting,
    Running,
    Stopping,
    #[default]
    Stopped,
}

pub fn service_words(state: State) -> &'static str {
    match state {
        State::Preparing => "being made",
        State::Starting => "starting",
        State::Running => "running",
        State::Stopping => "shutting down",
        State::Stopped => "stopped",
    }
}

pub fn app_words(state: State) -> &'static str {
    match state {
        State::Preparing => "Being made",
        State::Starting => "Starting",
        State::Running => "Running",
        State::Stopping => "Shutting down",
        State::Stopped => "Stopped",
    }
}

#[cfg(test)]
mod tests;
