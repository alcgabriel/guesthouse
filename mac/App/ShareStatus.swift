// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Where a machine's screen sharing stands, as the agent last said, and the words for it.
nonisolated struct ShareStatus: Equatable {
    enum State: String {
        case off, starting, listening, failed
    }

    var state: State
    var port: Int?
    /// The host key's fingerprint, for comparing on the viewer.
    var fingerprint: String?
    var pairing: Bool
    /// When an open pairing closes.
    var pairingUntil: Date?
    /// The name of the viewer connected now.
    var viewer: String?
    /// The device that paired last.
    var paired: String?
    /// Why pairing last closed: paired, declined, timeout, asked or other.
    var closedReason: String?
    /// A device waiting to be accepted or declined.
    var pending: Pending?
    /// The devices the host trusts, in the order they were paired.
    var devices: [Device] = []
    var reason: String?

    /// A device the host trusts. Of what a device may do, only control matters here: the host
    /// serves video and input, so clipboard, files and sound have nothing to switch.
    struct Device: Equatable, Identifiable {
        var fingerprint: String
        var name: String
        var connected: Bool
        /// False: view-only; what the device types is not used.
        var control: Bool

        var id: String { fingerprint }

        /// "Viewing now" or "Not connected".
        var statusText: String {
            connected ? String(localized: "Viewing now") : String(localized: "Not connected")
        }
    }

    /// A new device and the code it shows too, for the person to compare.
    struct Pending: Equatable {
        var name: String
        var code: String
        /// When the owner's time runs out, from what the host said when it came.
        var until: Date
    }

    static let off = ShareStatus(state: .off, port: nil, fingerprint: nil, pairing: false, pairingUntil: nil, viewer: nil, paired: nil, closedReason: nil, pending: nil, reason: nil)

    /// Reads the agent's `share` event, or one entry of a listing.
    init?(json: [String: Any]) {
        guard let name = json["state"] as? String, let state = State(rawValue: name) else { return nil }
        self.state = state
        port = json["port"] as? Int
        fingerprint = json["fingerprint"] as? String
        pairing = json["pairing"] as? Bool ?? false
        pairingUntil = (json["pairing_until_ms"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        viewer = json["viewer"] as? String
        paired = json["paired"] as? String
        closedReason = json["closed_reason"] as? String
        devices = (json["devices"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let fingerprint = entry["fingerprint"] as? String else { return nil }
            let permissions = entry["permissions"] as? [String: Any]
            return Device(
                fingerprint: fingerprint,
                name: entry["name"] as? String ?? fingerprint,
                connected: entry["connected"] as? Bool ?? false,
                control: permissions?["input"] as? Bool ?? true)
        }
        if let device = json["pending"] as? [String: Any], let name = device["name"] as? String,
           let code = device["code"] as? String {
            let seconds = (device["seconds"] as? Double) ?? 60
            pending = Pending(name: name, code: code, until: Date().addingTimeInterval(seconds))
        }
        reason = json["reason"] as? String
    }

    init(state: State, port: Int?, fingerprint: String?, pairing: Bool, pairingUntil: Date?, viewer: String?, paired: String? = nil, closedReason: String? = nil, pending: Pending? = nil, reason: String?) {
        self.state = state
        self.port = port
        self.fingerprint = fingerprint
        self.pairing = pairing
        self.pairingUntil = pairingUntil
        self.viewer = viewer
        self.paired = paired
        self.closedReason = closedReason
        self.pending = pending
        self.reason = reason
    }

    /// One line on where viewing from other devices stands. `allowed` is the machine's setting
    /// and `machineRunning` whether the machine is up, since the screen is only shared then.
    static func headline(allowed: Bool, machineRunning: Bool, share: ShareStatus) -> String {
        guard allowed else { return String(localized: "Off. Nothing is listening for other devices.") }
        guard machineRunning else { return String(localized: "On. The screen is shared once the machine is running.") }
        switch share.state {
        case .off, .starting:
            return String(localized: "Starting to share the screen…")
        case .listening:
            if let viewer = share.viewer { return String(localized: "\(viewer) is viewing this machine.") }
            return String(localized: "Ready. A paired device can connect.")
        case .failed:
            let why = share.reason ?? String(localized: "Something went wrong.")
            return String(localized: "The screen could not be shared: \(why)")
        }
    }

    /// The steps for connecting a new device, which are those the host really has: pairing is
    /// opened here, the device connects to the address and waits, and the person here compares
    /// the code and accepts.
    static var pairingSteps: [String] {
        [
            String(localized: "In remoteman on the other device, add a computer and enter the address above."),
            String(localized: "If remoteman shows a fingerprint, check that it matches the one above."),
            String(localized: "The device waits, and its name and a code appear here. Check that the code matches the one on the device, then press Accept. Pairing closes when the device has been answered, or when the time is up."),
        ]
    }

    /// How a device already paired connects.
    static var pairedHint: String {
        String(localized: "A device that is already paired connects to the address above. To add another device, press Pair a New Device.")
    }

    /// The line for the check that has to be made before Accept.
    static var compareCodeLine: String {
        String(localized: "Check that this code matches the one shown on the device before you press Accept.")
    }

    /// What to say about pairing while it is closed, by how it last ended.
    var closedText: String {
        switch closedReason {
        case "paired":
            guard let paired else { return String(localized: "Closed. A device was paired.") }
            return String(localized: "Closed. \(paired) was paired.")
        case "declined":
            return String(localized: "Closed. The device was turned away. Press Pair a New Device to try again.")
        case "timeout":
            return String(localized: "Closed. Nobody paired in time.")
        default:
            return String(localized: "Closed")
        }
    }

    /// The host key's fingerprint in the first 16 characters, grouped in fours, which is what
    /// fits on a line; the whole one is in the tooltip and is what Copy takes.
    var shortFingerprint: String? {
        guard let fingerprint else { return nil }
        let head = fingerprint.prefix(16)
        return stride(from: 0, to: head.count, by: 4)
            .map { head.dropFirst($0).prefix(4) }
            .joined(separator: " ") + (fingerprint.count > 16 ? "…" : "")
    }

    /// Whole seconds until the open pairing ends, or nil when it is not open (or has no end).
    func secondsLeft(now: Date) -> Int? {
        guard pairing, let until = pairingUntil, until > now else { return nil }
        return Int(until.timeIntervalSince(now).rounded(.up))
    }

    /// One line for `--print-states`: `share: NAME listening port 7792 pairing closed ...`, with the
    /// waiting device and its code, the viewer and the reason when there are any.
    func printLine(machine: String) -> String {
        var parts = ["share: \(machine) \(state.rawValue)"]
        if let port { parts.append("port \(port)") }
        parts.append("pairing \(pairing ? "open" : "closed")")
        if let pending { parts.append("pending \(pending.name) code \(pending.code)") }
        if let paired { parts.append("paired \(paired)") }
        if let closedReason { parts.append("closed because \(closedReason)") }
        if let viewer { parts.append("viewer \(viewer)") }
        if let reason { parts.append("reason: \(reason)") }
        return parts.joined(separator: " ")
    }

    /// The reminder about the network, said once in the pane.
    static var networkWarning: String {
        String(localized: "Devices on the same network can reach this machine's screen once they are paired.")
    }
}
