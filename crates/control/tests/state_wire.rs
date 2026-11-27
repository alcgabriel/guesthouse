//! A machine's state as it goes over the pipe, held as it is: an old app reads these names and no
//! other, so every state and every event is held as the JSON it is, both ways, and a name the pipe
//! never sent is refused as it was.

use guesthouse_control::{Event, State};
use serde_json::{Value, json};

const STATES: [(State, &str); 5] = [
    (State::Preparing, "preparing"),
    (State::Starting, "starting"),
    (State::Running, "running"),
    (State::Stopping, "stopping"),
    (State::Stopped, "stopped"),
];

#[test]
fn every_state_is_its_wire_name() {
    for (state, name) in STATES {
        assert_eq!(serde_json::to_value(state).unwrap(), json!(name));
        assert_eq!(serde_json::from_value::<State>(json!(name)).unwrap(), state);
    }
    assert_eq!(State::default(), State::Stopped);
}

#[test]
fn every_event_is_its_wire_line() {
    for (state, name) in STATES {
        let line = json!({"kind": "state", "text": name});
        assert_eq!(serde_json::to_value(Event::State(state)).unwrap(), line);
        assert_eq!(serde_json::from_value::<Event>(line).unwrap(), Event::State(state));
    }
    for (event, kind) in [
        (Event::Note("n".into()), "note"),
        (Event::Problem("p".into()), "problem"),
        (Event::Guest("g".into()), "guest"),
        (Event::Report("r".into()), "report"),
    ] {
        let text = match &event {
            Event::Note(text) | Event::Problem(text) | Event::Guest(text) | Event::Report(text) => {
                text.clone()
            }
            Event::State(_) => unreachable!(),
        };
        let line = json!({"kind": kind, "text": text});
        assert_eq!(serde_json::to_value(&event).unwrap(), line);
        assert_eq!(serde_json::from_value::<Event>(line).unwrap(), event);
    }
    assert_eq!(
        serde_json::to_string(&Event::State(State::Running)).unwrap(),
        r#"{"kind":"state","text":"running"}"#
    );
}

#[test]
fn a_name_the_pipe_never_sent_is_refused() {
    for name in ["Running", "off", "failed", "installing", "shutting_down", ""] {
        assert!(serde_json::from_value::<State>(json!(name)).is_err(), "{name}");
        assert!(serde_json::from_value::<Event>(json!({"kind": "state", "text": name})).is_err(), "{name}");
    }
    assert!(serde_json::from_value::<Event>(json!({"kind": "other", "text": "x"})).is_err());
    assert!(serde_json::from_value::<State>(Value::Null).is_err());
}
