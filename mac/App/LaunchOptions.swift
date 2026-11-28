// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Launch arguments for trying the app by hand or from a script.
nonisolated enum LaunchOptions {
    /// `--screen NAME`: open the screen of the machine called NAME at launch.
    static let screen: String? = value(after: "--screen")

    /// `--print-stats`: print each screen's frame counts to standard output once a second.
    static let printStats = CommandLine.arguments.contains("--print-stats")

    /// `--print-states`: print each machine's state, as the agent reports it, when it changes.
    static let printStates = CommandLine.arguments.contains("--print-states")

    /// `--start NAME`, `--shut-down NAME`, `--force-off NAME`: ask the agent for that once
    /// connected.
    static let start: String? = value(after: "--start")
    static let shutDown: String? = value(after: "--shut-down")
    static let forceOff: String? = value(after: "--force-off")

    /// `--share on|off NAME`: allow or forbid viewing NAME from other devices, and share it now if it
    /// runs. `--pair NAME`: open pairing on NAME once it is shared.
    static let share: (on: Bool, name: String)? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--share"), index + 2 < arguments.count,
              ["on", "off"].contains(arguments[index + 1])
        else { return nil }
        return (arguments[index + 1] == "on", arguments[index + 2])
    }()
    static let pair: String? = value(after: "--pair")
    /// `--accept NAME` and `--decline NAME`: answer the device waiting to pair with NAME.
    static let accept: String? = value(after: "--accept")
    static let decline: String? = value(after: "--decline")

    /// `--install windows|ubuntu NAME [--installer FILE]`: install a guest in a new machine called
    /// NAME (Windows needs the installer file); `--install-status NAME` prints where it stands and
    /// `--install-cancel NAME` stops it. With `GUESTHOUSE_INSTALL_FAKE` set in the agent's
    /// environment it is all stand-ins, with no download and no machine.
    static let install: (guest: String, name: String)? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--install"), index + 2 < arguments.count,
              ["windows", "ubuntu"].contains(arguments[index + 1])
        else { return nil }
        return (arguments[index + 1], arguments[index + 2])
    }()
    static let installer: String? = value(after: "--installer")
    static let installStatus: String? = value(after: "--install-status")
    static let installCancel: String? = value(after: "--install-cancel")

    /// `--tab overview|sharing|hardware|details`: the page a machine opens on, for trying each.
    static let tab: String? = value(after: "--tab")

    /// `--quit-after SECONDS`: quit the app that many seconds after launch.
    static let quitAfter: Double? = value(after: "--quit-after").flatMap(Double.init)

    /// `--unregister-agent`: take the agent out of launchd and leave.
    static let unregisterAgent = CommandLine.arguments.contains("--unregister-agent")

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
