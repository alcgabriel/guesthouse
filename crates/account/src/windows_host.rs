//! The Windows host's rules for a guest's administrator. The app and the service check a name with
//! [`valid_user`] (the same for a Windows and an Ubuntu guest), the answer file is never given one of
//! the accounts every Windows has ([`windows_account`]), and an Ubuntu guest's install checks its user
//! with [`valid_ubuntu_user`].

/// Whether `name` can be a guest's administrator in both systems: Ubuntu's rule for a user, which
/// Windows takes too, and not one of Windows' own accounts, which are disabled.
pub fn valid_user(name: &str) -> bool {
    const LONGEST: usize = 20;
    const WINDOWS_OWN: [&str; 4] = ["administrator", "defaultaccount", "guest", "wdagutilityaccount"];
    let mut characters = name.chars();
    name.len() <= LONGEST
        && characters.next().is_some_and(|first| first.is_ascii_lowercase())
        && characters.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
        && !WINDOWS_OWN.contains(&name)
}

/// The accounts every Windows has. The answer file's account takes the existing one when the name
/// matches, whatever its case, and those are disabled, so none can be the guest's administrator.
pub const WINDOWS_ACCOUNTS: [&str; 4] = ["Administrator", "DefaultAccount", "Guest", "WDAGUtilityAccount"];

/// Whether `user` is one of Windows' own accounts, and so can't be made as a new one.
pub fn windows_account(user: &str) -> bool {
    WINDOWS_ACCOUNTS.iter().any(|account| account.eq_ignore_ascii_case(user))
}

/// A name Ubuntu takes for a user, and that the install script reads back whole.
pub fn valid_ubuntu_user(name: &str) -> bool {
    let mut characters = name.chars();
    characters.next().is_some_and(|first| first.is_ascii_lowercase())
        && characters.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
}

#[cfg(test)]
mod tests;
