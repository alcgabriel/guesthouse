//! The app's own settings, the ones its Settings page holds, kept in `app-settings.json` in this
//! user's local app-data folder (`%LOCALAPPDATA%\Guesthouse`), beside the viewer's identities. The
//! machines' settings are the service's, and none of these are. Whether the app opens when the
//! person signs in isn't here: Windows keeps that, in the user's Run key (see system.rs).
//!
//! It's read once as the app starts and written whole, in one step, each time one changes, through
//! `guesthouse_basics::json_file::write_json`. A file that can't be read, or a field that's missing
//! or of a kind this app doesn't know, is the default, so an older or newer app's file never stops
//! the app from opening.

// Off Windows only the tests use these.
#![cfg_attr(not(windows), allow(dead_code))]

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// The file's name, in the app's folder.
const FILE: &str = "app-settings.json";

/// Light or dark, or as Windows is.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Theme {
    #[default]
    System,
    Light,
    Dark,
}

impl Theme {
    pub const ALL: [Theme; 3] = [Theme::System, Theme::Light, Theme::Dark];

    /// Its words in the list.
    pub fn label(self) -> &'static str {
        match self {
            Theme::System => "Windows' setting",
            Theme::Light => "Light",
            Theme::Dark => "Dark",
        }
    }
}

/// The app's settings.
#[derive(Clone, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Preferences {
    /// Look for a newer Guesthouse when the app starts, and once a day while it's open.
    pub look_by_itself: bool,
    pub theme: Theme,
}

impl Default for Preferences {
    fn default() -> Self {
        Preferences { look_by_itself: true, theme: Theme::System }
    }
}

impl Preferences {
    /// The settings a file's text holds: the default for anything it doesn't say, or says in a way
    /// this app doesn't know.
    pub fn parse(text: &str) -> Preferences {
        let Ok(serde_json::Value::Object(fields)) = serde_json::from_str::<serde_json::Value>(text) else {
            return Preferences::default();
        };
        let mut preferences = Preferences::default();
        // A field at a time, so one this app can't read leaves the others as they were written.
        if let Some(on) = fields.get("look_by_itself").and_then(serde_json::Value::as_bool) {
            preferences.look_by_itself = on;
        }
        if let Some(Ok(theme)) = fields.get("theme").map(Theme::deserialize) {
            preferences.theme = theme;
        }
        preferences
    }

    /// The settings kept in `folder`, or the default when there are none yet.
    pub fn read(folder: &Path) -> Preferences {
        std::fs::read_to_string(folder.join(FILE)).map(|text| Preferences::parse(&text)).unwrap_or_default()
    }

    /// Keeps them in `folder`, in one step.
    pub fn write(&self, folder: &Path) -> std::io::Result<()> {
        guesthouse_basics::json_file::write_json(&folder.join(FILE), self)
    }
}

/// The app's own folder in this user's local app data, where its settings and anything else of the
/// app's that's this user's alone are kept. `None` when Windows doesn't say where that is.
pub fn folder() -> Option<PathBuf> {
    std::env::var_os("LOCALAPPDATA").map(|base| PathBuf::from(base).join("Guesthouse"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_file_or_a_garbled_one_is_the_default() {
        assert_eq!(Preferences::parse(""), Preferences::default());
        assert_eq!(Preferences::parse("not json"), Preferences::default());
        assert_eq!(Preferences::parse("[1, 2]"), Preferences::default());
        let default = Preferences::default();
        assert!(default.look_by_itself, "looking is on until it's turned off");
        assert_eq!(default.theme, Theme::System);
    }

    #[test]
    fn what_a_file_says_is_kept_and_what_it_doesnt_know_is_the_default() {
        let read = Preferences::parse(r#"{"look_by_itself": false, "theme": "dark"}"#);
        assert_eq!(read, Preferences { look_by_itself: false, theme: Theme::Dark });
        // A newer app's theme, or a field of the wrong kind, leaves the rest as written.
        let read = Preferences::parse(r#"{"look_by_itself": false, "theme": "sepia", "later": 3}"#);
        assert_eq!(read, Preferences { look_by_itself: false, theme: Theme::System });
        let read = Preferences::parse(r#"{"look_by_itself": "no", "theme": "light"}"#);
        assert_eq!(read, Preferences { look_by_itself: true, theme: Theme::Light });
    }

    #[test]
    fn they_are_written_and_read_back_whole() {
        let folder = std::env::temp_dir().join(format!("gh-app-settings-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        assert_eq!(Preferences::read(&folder), Preferences::default(), "none yet");
        let chosen = Preferences { look_by_itself: false, theme: Theme::Light };
        chosen.write(&folder).unwrap();
        assert_eq!(Preferences::read(&folder), chosen);
        let text = std::fs::read_to_string(folder.join(FILE)).unwrap();
        assert!(text.contains(r#""theme": "light""#), "{text}");
        assert!(!folder.join(format!("{FILE}.new")).exists(), "the step's own file is renamed over it");
        std::fs::remove_dir_all(&folder).unwrap();
    }

    #[test]
    fn each_theme_has_its_words() {
        let labels: Vec<&str> = Theme::ALL.iter().map(|theme| theme.label()).collect();
        assert_eq!(labels, ["Windows' setting", "Light", "Dark"]);
    }
}
