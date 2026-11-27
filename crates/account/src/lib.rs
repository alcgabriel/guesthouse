//! The rules for a guest's account, as each host has them. The hosts disagree (on the reserved
//! names, the longest name, whether a capital or a dot is taken, and the password), and a rule made
//! tighter would refuse an account a machine already has, so each host's rules are a module of their
//! own and none stands in for another: [`linux_host`] and [`windows_host`].
//!
//! Making a password and keeping it stay with each host, as they draw on the system.

pub mod linux_host;
pub mod windows_host;
