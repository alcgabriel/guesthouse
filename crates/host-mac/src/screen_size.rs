//! The size a machine's screen should be, as the app works it out from the machine's window.
//!
//! This is the app's half of "the screen follows the window". When a resize of the window ends
//! the app says how many points the window is, how many pixels the screen should have and the
//! scaling to set (200 for Sharp, 100 for Standard). Today this only records the last answer for
//! each machine and does nothing with it: telling the guest needs a way in that the guests do not
//! offer yet (`notes/mac-app-screen-size.md` says what each side must provide).

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

/// What the app asks the machine's screen to be.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Wanted {
    pub width_px: u32,
    pub height_px: u32,
    pub scaling_percent: u32,
}

/// The scalings that mean something to a guest.
pub const SCALINGS: [u32; 2] = [100, 200];

fn recorded() -> &'static Mutex<HashMap<String, Wanted>> {
    static RECORDED: OnceLock<Mutex<HashMap<String, Wanted>>> = OnceLock::new();
    RECORDED.get_or_init(Default::default)
}

/// Records what machine `id`'s screen should be, if it is something a screen can be.
pub fn record(id: &str, wanted: Wanted) -> Result<(), String> {
    if wanted.width_px == 0 || wanted.height_px == 0 {
        return Err("A screen needs a width and a height.".into());
    }
    if !SCALINGS.contains(&wanted.scaling_percent) {
        return Err(format!(
            "{}% is not a scaling a guest takes (100 or 200).",
            wanted.scaling_percent
        ));
    }
    recorded()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .insert(id.to_string(), wanted);
    Ok(())
}

/// The last size recorded for machine `id`.
pub fn last(id: &str) -> Option<Wanted> {
    recorded()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get(id)
        .copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_last_size_asked_for_is_the_one_kept() {
        let first = Wanted {
            width_px: 2360,
            height_px: 1392,
            scaling_percent: 200,
        };
        let second = Wanted {
            width_px: 1180,
            height_px: 696,
            scaling_percent: 100,
        };
        assert_eq!(last("screen-size-test"), None);
        record("screen-size-test", first).unwrap();
        record("screen-size-test", second).unwrap();
        assert_eq!(last("screen-size-test"), Some(second));
    }

    #[test]
    fn nothing_that_is_not_a_screen_is_kept() {
        let empty = Wanted {
            width_px: 0,
            height_px: 10,
            scaling_percent: 100,
        };
        assert!(record("screen-size-bad", empty).is_err());
        let odd = Wanted {
            width_px: 10,
            height_px: 10,
            scaling_percent: 150,
        };
        assert!(record("screen-size-bad", odd).unwrap_err().contains("150%"));
        assert_eq!(last("screen-size-bad"), None);
    }
}
