//! How the app says a machine's state, held word for word as it is.

use super::state_words;
use guesthouse_control::State;

#[test]
fn each_state_in_the_apps_words() {
    for (state, said) in [
        (State::Preparing, "Being made"),
        (State::Starting, "Starting"),
        (State::Running, "Running"),
        (State::Stopping, "Shutting down"),
        (State::Stopped, "Stopped"),
    ] {
        assert_eq!(state_words(state), said);
    }
}
