//! The Linux host's machine states and the word each is shown with. They have no serialized form:
//! the app shows them by these words.

/// Where a machine stands, as the Linux app shows it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum State {
    #[default]
    Off,
    Starting,
    Installing,
    Running,
    Stopping,
}

impl State {
    pub fn name(self) -> &'static str {
        match self {
            Self::Off => "Off",
            Self::Starting => "Starting",
            Self::Installing => "Installing",
            Self::Running => "Running",
            Self::Stopping => "Stopping",
        }
    }
}

#[cfg(test)]
mod tests;
