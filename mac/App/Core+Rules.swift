import Foundation
import GuesthouseCore

/// The rules of a machine's page, asked of the core (`rules.rs`): what a state offers, whether
/// Start and Open Screen work, whether an install is shown, the order the start checks run in.
/// The app draws what comes back and keeps none of the rules.
enum Rules {
    /// One rule's answer as the core gave it, or an empty one.
    fileprivate static func ask(_ request: [String: Any]) -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let json = String(data: data, encoding: .utf8),
              let text = guesthouse_rule(json)
        else { return [:] }
        defer { guesthouse_string_free(text) }
        let object = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8))
        return object as? [String: Any] ?? [:]
    }

    private static func yes(_ request: [String: Any]) -> Bool {
        ask(request)["yes"] as? Bool ?? false
    }

    static func canOpenScreen(hasScreen: Bool, startable: Bool, state: String) -> Bool {
        yes(["rule": "can_open_screen", "has_screen": hasScreen, "startable": startable, "state": state])
    }

    static func canStart(startable: Bool, problem: Bool, agentConnected: Bool, state: String) -> Bool {
        yes([
            "rule": "can_start", "startable": startable, "problem": problem,
            "agent_connected": agentConnected, "state": state,
        ])
    }

    static func showsInstall(installState: String, seen: Bool) -> Bool {
        yes(["rule": "shows_install", "install_state": installState, "seen": seen])
    }

    /// The start checks in the order they run.
    static var startCheckOrder: [String] {
        ask(["rule": "start_check_order"])["order"] as? [String] ?? []
    }
}

extension MachineStatus {
    /// A machine whose process is, or may be, there.
    var isAlive: Bool { Rules.ask(["rule": "is_alive", "state": state])["yes"] as? Bool ?? false }

    /// Force Off is for a machine that is coming up or running, and for a shutdown that has not
    /// worked in time.
    var canForceOff: Bool { Rules.ask(["rule": "can_force_off", "state": state])["yes"] as? Bool ?? false }

    /// The action that makes sense next, if any.
    var nextStep: NextStep? {
        switch Rules.ask(["rule": "next_step", "state": state])["step"] as? String {
        case "start": .start
        case "open_screen": .openScreen
        case "force_off": .forceOff
        default: nil
        }
    }
}
