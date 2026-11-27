//! Bug reports, the part with no host in it, so every host builds on one implementation: what the
//! report server and the hosts agree on (`contract`), the kinds of problem (`kind`) and the
//! server's answer (`answer`).
//!
//! Each host gathers its own files and facts, packs them and runs `curl` its own way. Where the
//! hosts still differ in what they do with a report, each host's way is kept as it is, and the
//! difference is said where it lives.
//!
//! Nothing here calls the system, the network or a hypervisor, so every host can build on it.

pub mod answer;
pub mod contract;
pub mod kind;
