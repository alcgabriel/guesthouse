//! The Windows host's rules at their edges, as they were held in `control` and `host-windows` before
//! they moved here.

use super::*;

#[test]
fn names_taken_and_refused() {
    for name in
        ["a", "guesthouse", "a-b_2", "a0", "z_", &"x".repeat(20), "admin", "root", "system", "defaultuser0"]
    {
        assert!(valid_user(name), "{name:?}");
    }
    for name in [
        "",
        "_a",
        "A",
        "aB",
        "1a",
        "-a",
        "a.b",
        "a b",
        "é",
        &"x".repeat(21),
        "administrator",
        "defaultaccount",
        "guest",
        "wdagutilityaccount",
    ] {
        assert!(!valid_user(name), "{name:?}");
    }
}

#[test]
fn the_four_accounts_in_any_case() {
    for name in
        ["Administrator", "administrator", "ADMINISTRATOR", "DefaultAccount", "guest", "WDAGUtilityAccount"]
    {
        assert!(windows_account(name), "{name}");
    }
    for name in ["", "admin", "root", "system", "defaultuser0", "krbtgt", "guesthouse", "guest "] {
        assert!(!windows_account(name), "{name:?}");
    }
}

#[test]
fn a_user_name_at_each_edge() {
    for name in ["a", "z", "a0", "a-", "a_", "root", "administrator", &"x".repeat(100)] {
        assert!(valid_ubuntu_user(name), "{name:?}");
    }
    for name in ["_a", "-a", "0a", "A", "aB", "a.b", "é", "a\n"] {
        assert!(!valid_ubuntu_user(name), "{name:?}");
    }
}
