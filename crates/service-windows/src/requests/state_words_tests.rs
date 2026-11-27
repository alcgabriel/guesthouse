//! How the service says a machine's state in a refusal, held word for word as it is.

use super::words;
use guesthouse_control::State;

#[test]
fn each_state_in_the_services_words() {
    for (state, said) in [
        (State::Preparing, "being made"),
        (State::Starting, "starting"),
        (State::Running, "running"),
        (State::Stopping, "shutting down"),
        (State::Stopped, "stopped"),
    ] {
        assert_eq!(words(state), said);
    }
}
