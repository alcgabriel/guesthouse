//! A machine's states and the words they are shown with, as each host has them. The hosts' states
//! differ, and the Windows host's names go over its pipe, where an app of another version reads
//! them, so each host's states are a module of their own, with their names as they are and no new
//! ones: [`linux_host`] and [`windows_host`].

pub mod linux_host;
pub mod windows_host;
