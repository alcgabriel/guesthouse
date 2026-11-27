//! The Windows host's rule for the guest's administrator, held as it is: Ubuntu's rule for a user,
//! at most 20 bytes, and not one of the four accounts every Windows has, in lower case.

use guesthouse_control::valid_user;

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
