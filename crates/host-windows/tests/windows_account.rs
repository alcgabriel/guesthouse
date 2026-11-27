//! The four accounts every Windows has, which the Windows host never makes as a guest's own, held as
//! they are: matched in any case, and only these four.

use guesthouse_host_windows::guest::windows_account;

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
