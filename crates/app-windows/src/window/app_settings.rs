//! The app's own Settings page, from the gear in the title bar, with Back to where it was opened
//! from: whether a newer Guesthouse is out and looking for one, how the app looks and whether it
//! opens at sign-in, and Report a problem, its versions and its licences. It can be reached when the
//! service can't be, as a service of another version is what an update puts right.

use windows_reactor::*;

use super::parts::*;
use crate::app::{Main, Message};
use crate::preferences::Theme;
use crate::update::Phase;

/// The widest the page is, as the design has it.
const PAGE_WIDTH: f64 = 900.0;
/// The widest the theme's list is.
const THEME_WIDTH: f64 = 200.0;

/// The remoteman an installer carries, as its one pin says.
const REMOTEMAN_PIN: &str = include_str!("../../../remote-view/remoteman.json");

/// The gear that opens the app's settings, in the title bar, with Guesthouse's yellow dot at its
/// corner while a newer Guesthouse is out. Its name says so, for those who can't see the dot.
pub fn gear(main: &Main, context: &ViewContext<Main>) -> View {
    let dot = main.updates.dot();
    let mut inside: Vec<View> = vec![icon(glyph::SETTINGS, 16.0).into()];
    if dot {
        inside.push(
            Ellipse::new()
                .width(8.0)
                .height(8.0)
                .fill(Color::rgb(0xF6, 0xC4, 0x2D))
                .stroke(Color::rgb(0x8A, 0x53, 0x00))
                .stroke_thickness(1.0)
                .horizontal_alignment(HorizontalAlignment::Right)
                .vertical_alignment(VerticalAlignment::Top)
                .margin(Thickness::new(0.0, -6.0, -8.0, 0.0))
                .into(),
        );
    }
    let name = if dot { "Settings, an update is out" } else { "Settings" };
    Button::new()
        .content(Grid::new().children(inside))
        .style(ButtonStyle::Subtle)
        .automation_name(name)
        .on_click(context.message(Message::OpenSettings))
        .tooltip(name)
}

pub fn page(main: &Main, context: &ViewContext<Main>) -> View {
    let heading = Border::new()
        .is_tab_stop(true)
        .element_ref(&main.focus)
        .automation_name("Settings")
        .margin(Thickness::new(0.0, 12.0, 0.0, 4.0))
        .content(display("Settings"));
    let mut parts: Vec<View> = vec![heading.into()];
    parts.push(titled("Updates", update_rows(main, context)));
    parts.push(titled("This app", app_rows(main, context)));
    parts.push(titled("Help and about", about_rows(main, context)));
    scrolled(parts, PAGE_WIDTH)
}

/// A section of the page: its heading over a card of its rows.
fn titled(heading: &str, rows: Vec<View>) -> View {
    StackPanel::new()
        .spacing(8.0)
        .children((strong(heading).foreground(ThemeBrush::SecondaryText), group(rows)))
        .into()
}

// ---- Updates ----

fn update_rows(main: &Main, context: &ViewContext<Main>) -> Vec<View> {
    let mut rows = vec![status_row(main, context)];
    if main.updates.phase == Phase::NotInstalled {
        return rows;
    }
    let turned_off = crate::app::looking_turned_off();
    let line = if turned_off {
        "GUESTHOUSE_UPDATE_CHECK=0 turns it off for as long as it's set."
    } else {
        "Asks files.ruxn.com when the app starts, and once a day while it's open."
    };
    rows.push(row(
        "Look for updates by itself",
        &[line],
        Some(toggle(
            "Look for updates by itself",
            main.preferences.look_by_itself && !turned_off,
            !turned_off,
            context.callback(Message::SetLookByItself),
        )),
    ));
    rows
}

/// Where the looking stands, and what can be done about it.
fn status_row(main: &Main, context: &ViewContext<Main>) -> View {
    let current = guesthouse_control::WINDOWS_VERSION;
    let look = |text: &str| -> View {
        button(text, context.message(Message::Look), false)
            .automation_name("Look for updates now")
            .is_enabled(main.updates.can_look())
            .into()
    };
    let looked = |at: u64| format!("Looked at {}.", crate::system::local_time(at));
    match &main.updates.phase {
        Phase::NotInstalled => row(
            "This is a build of the repo",
            &[
                "It's whatever it was built from, so it isn't offered updates. An installed Guesthouse looks for them.",
            ],
            None,
        ),
        Phase::NotLooked => {
            row(&format!("Guesthouse {current}"), &["Not looked yet."], Some(look("Look now")))
        }
        Phase::Looking => row_with(
            &format!("Guesthouse {current}"),
            side_by_side((ring(16.0), caption("Looking for a newer Guesthouse."))),
            None,
            Some(look("Look now")),
        ),
        Phase::Newest { looked: at } => {
            row(&format!("Guesthouse {current} is the newest"), &[&looked(*at)], Some(look("Look now")))
        }
        Phase::CantTell { why, looked: at } => row_with(
            "Couldn't tell whether a newer Guesthouse is out",
            StackPanel::new().children((bad(why.words()), caption(&looked(*at)))),
            None,
            Some(look("Look again")),
        ),
        Phase::Newer { latest, .. } => {
            let words = format!(
                "You have {current}. Download the installer and run it: it keeps your machines, and asks each \
                 running one to shut down first."
            );
            let download = button("Download", context.message(Message::GetUpdate), true)
                .automation_name(format!("Download Guesthouse {}", latest.version));
            let mut buttons: Vec<View> = vec![download.into()];
            if main.updates.dot() {
                buttons.push(button("Not now", context.message(Message::LaterUpdate), false).into());
            }
            buttons.push(notes_link(&latest.version, context));
            StackPanel::new()
                .spacing(10.0)
                .margin(Thickness::new(0.0, 14.0, 0.0, 14.0))
                .children((
                    StackPanel::new().spacing(2.0).children((
                        strong(&format!("Guesthouse {} is out", latest.version)),
                        caption(&words),
                    )),
                    side_by_side(buttons),
                ))
                .into()
        }
    }
}

/// The link to `version`'s release notes.
fn notes_link(version: &str, context: &ViewContext<Main>) -> View {
    HyperlinkButton::new()
        .content("Release notes")
        .automation_name(format!("Release notes of Guesthouse {version}"))
        .on_click(context.message(Message::ReleaseNotes(version.to_owned())))
        .into()
}

// ---- This app ----

fn app_rows(main: &Main, context: &ViewContext<Main>) -> Vec<View> {
    let themes: Vec<String> = Theme::ALL.iter().map(|theme| theme.label().to_owned()).collect();
    let chosen = Theme::ALL.iter().position(|theme| *theme == main.preferences.theme);
    let theme = ComboBox::new()
        .items_source(themes)
        .selected_index(chosen)
        .width(THEME_WIDTH)
        .automation_name("Theme")
        .on_selection_changed(context.callback(Message::SetTheme));
    let mut rows = vec![row("Theme", &["Light or dark, or as Windows is."], Some(theme.into()))];
    // Only an installed app has a place of its own to open from.
    if main.installed {
        rows.push(row(
            "Open when I sign in",
            &["The service starts with Windows anyway; this is only the window."],
            Some(toggle(
                "Open when I sign in",
                main.opens_at_sign_in,
                true,
                context.callback(Message::SetSignIn),
            )),
        ));
    }
    rows
}

// ---- Help and about ----

fn about_rows(main: &Main, context: &ViewContext<Main>) -> Vec<View> {
    let current = guesthouse_control::WINDOWS_VERSION;
    let report = button("Report a problem", context.message(Message::OpenReport), false);
    let open = button("Open", context.message(Message::Licences), false).automation_name("Open the licences");
    let licences = if main.installed {
        "THIRD-PARTY.md in the install folder: WinFsp, remoteman, FFmpeg, the Windows App Runtime."
    } else {
        "THIRD-PARTY.md in the repo: WinFsp, remoteman, FFmpeg, the Windows App Runtime."
    };
    vec![
        row(
            "Report a problem",
            &["Prepare makes the report and shows you what's in it. Nothing is sent until you press Send."],
            Some(report.into()),
        ),
        row(&format!("Guesthouse {current}"), &[&versions(main)], Some(notes_link(current, context))),
        row("Licences", &[licences], Some(open.into())),
    ]
}

/// The versions of the app, the service and the remoteman an installer carries.
fn versions(main: &Main) -> String {
    let current = guesthouse_control::WINDOWS_VERSION;
    let service = match main.status() {
        Some(status) if status.version == current => format!("App and service {current}"),
        Some(status) => format!("App {current}, service {}", status.version),
        None => format!("App {current}; the service isn't answering"),
    };
    match remoteman_pin().filter(|_| main.installed) {
        Some(remoteman) => format!("{service}, remoteman {remoteman}."),
        None => format!("{service}."),
    }
}

/// The version of remoteman its pin names.
fn remoteman_pin() -> Option<String> {
    let pin: serde_json::Value = serde_json::from_str(REMOTEMAN_PIN).ok()?;
    pin.get("version")?.as_str().map(str::to_owned)
}
