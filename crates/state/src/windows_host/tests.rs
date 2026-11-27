//! The Windows host's states and both wordings, as they were held in `control`, the service and the
//! app before they moved here.

use super::*;

#[test]
fn each_state_its_wire_name_and_both_wordings() {
    for (state, wire, service, app) in [
        (State::Preparing, "\"preparing\"", "being made", "Being made"),
        (State::Starting, "\"starting\"", "starting", "Starting"),
        (State::Running, "\"running\"", "running", "Running"),
        (State::Stopping, "\"stopping\"", "shutting down", "Shutting down"),
        (State::Stopped, "\"stopped\"", "stopped", "Stopped"),
    ] {
        assert_eq!(serde_json::to_string(&state).unwrap(), wire);
        assert_eq!(serde_json::from_str::<State>(wire).unwrap(), state);
        assert_eq!((service_words(state), app_words(state)), (service, app));
    }
    assert_eq!(State::default(), State::Stopped);
    assert!(serde_json::from_str::<State>("\"failed\"").is_err());
}
