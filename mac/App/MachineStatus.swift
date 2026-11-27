// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Where a machine stands, as the agent last said.
nonisolated struct MachineStatus: Equatable {
    var state: String
    var reason: String?

    /// The state names are the shared ones (`off`, `starting`, `installing`, `running`, `stopping`,
    /// `stopping_stalled`, `failed`), as every host says them; `stopping_stalled` is a shutdown that
    /// has not worked in time.
    static let off = MachineStatus(state: "off", reason: nil)

    /// The one or two words for the sidebar and for VoiceOver.
    var title: String {
        switch state {
        case "starting": String(localized: "Starting")
        case "running": String(localized: "Running")
        case "stopping": String(localized: "Stopping")
        case "stopping_stalled": String(localized: "Still stopping")
        case "failed": String(localized: "Failed")
        default: String(localized: "Off")
        }
    }

    /// The state as the sidebar says it. One word for it everywhere: Off, as the Linux host says it.
    var plainTitle: String { title }

    /// What to do about it, when there is something sensible to do.
    enum NextStep: Equatable {
        case start
        case openScreen
        case forceOff
    }

    /// The state as a sentence about the machine called `name`.
    func sentence(for name: String) -> String {
        switch state {
        case "starting":
            String(localized: "\(name) is starting. This takes a few seconds.")
        case "running":
            String(localized: "\(name) is running.")
        case "stopping_stalled":
            String(localized: "\(name) is taking a long time to shut down. If it is stuck, Force Off ends it at once, and anything not saved in it is lost.")
        case "stopping":
            String(localized: "\(name) is shutting down. Windows is closing its programs.")
        case "failed":
            if let reason, !reason.isEmpty {
                String(localized: "\(name) stopped because something went wrong: \(reason)")
            } else {
                String(localized: "\(name) stopped because something went wrong.")
            }
        default:
            String(localized: "\(name) is turned off.")
        }
    }
}
