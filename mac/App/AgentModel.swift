// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import os

/// The agent's answer to one request.
nonisolated struct AgentAnswer {
    let ok: Bool
    let error: String?
    let statuses: [String: MachineStatus]?
    /// For a listing: the machines whose screen is being shared.
    var shares: [String: ShareStatus]? = nil
    /// For a listing or `install_status`: the installs. For `install`: the new machine's id.
    var installs: [String: InstallStatus]? = nil
    var machine: String? = nil

    static func failure(_ text: String) -> AgentAnswer {
        AgentAnswer(ok: false, error: text, statuses: nil)
    }
}

/// The app's side of the agent: finds or starts it, sends what the user asks, and keeps the
/// states the agent reports. Everything the window shows about running machines comes from here.
@Observable
final class AgentModel {
    /// Machine id (the folder's name) to its state; absent means stopped.
    private(set) var statuses: [String: MachineStatus] = [:]
    /// Machine id to where its install stands; absent means none.
    private(set) var installs: [String: InstallStatus] = [:]
    /// Machine id to where its screen sharing stands; absent means off.
    private(set) var shares: [String: ShareStatus] = [:]
    private(set) var connected = false
    /// Told whenever a machine's state or share changes, so the library can act on it.
    @ObservationIgnored var onChange: () -> Void = {}
    /// How the agent is reached, for Settings: what is live and why not the other.
    private(set) var route = String(localized: "Not connected")

    @ObservationIgnored private var link: AgentLink?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var pending: [Int: CheckedContinuation<AgentAnswer, Never>] = [:]
    @ObservationIgnored private var maintaining = false
    @ObservationIgnored private let log = Logger(subsystem: "com.ruxn.guesthouse", category: "agent")

    func status(of machine: Machine) -> MachineStatus {
        statuses[machine.agentID] ?? .off
    }

    func share(of machine: Machine) -> ShareStatus {
        shares[machine.agentID] ?? .off
    }

    /// Whether any machine is on its way up or running.
    var anyAlive: Bool { statuses.values.contains { $0.isAlive } }

    var aliveMachineIDs: [String] { statuses.filter { $0.value.isAlive }.map(\.key) }

    /// Connects, and keeps trying: an agent that went away is found or started again.
    func maintain() {
        guard !maintaining else { return }
        maintaining = true
        Task {
            while true {
                if !connected { await establish() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// `scale` is what a Linux guest draws its desktop at: 2 for Sharp, 1 for Standard.
    func start(_ machine: Machine, qemu: String, rmhost: String?, pvgHost: String?, scale: Int) async -> String? {
        var request: [String: Any] = ["op": "start", "machine": machine.agentID, "scale": scale]
        if !qemu.isEmpty { request["qemu"] = qemu }
        if let rmhost { request["rmhost"] = rmhost }
        if let pvgHost { request["pvg_host"] = pvgHost }
        return await ask(request).error
    }

    /// Starts or stops sharing a running machine's screen, and with `pairing` opens pairing
    /// for a short time. A share that is up is not restarted for that: rmhost is told.
    /// Answers or ends a pairing on a shared machine: `pair_accept`, `pair_decline` or
    /// `pair_close`.
    func pair(_ op: String, machine: Machine) async -> String? {
        await ask(["op": op, "machine": machine.agentID]).error
    }

    /// Allows or forbids `what` (`input` is control) for a trusted device.
    func deviceAllow(machine: Machine, fingerprint: String, what: String, on: Bool) async -> String? {
        await ask(["op": "device_allow", "machine": machine.agentID, "fingerprint": fingerprint, "what": what, "on": on]).error
    }

    /// Stops trusting a device (`device_revoke`) or disconnects the viewer (`device_drop`).
    func deviceRemove(machine: Machine, fingerprint: String) async -> String? {
        await ask(["op": "device_revoke", "machine": machine.agentID, "fingerprint": fingerprint]).error
    }

    func deviceDisconnect(machine: Machine) async -> String? {
        await ask(["op": "device_drop", "machine": machine.agentID]).error
    }

    /// Starts installing `guest` ("windows" or "ubuntu") in a new machine called `name`. Returns
    /// the machine's id, or why it did not start.
    func install(
        name: String, guest: String, file: String?, qemu: String?, pvgHost: String?,
        sizes: InstallSizes? = nil, password: String? = nil, desktop: String? = nil
    ) async -> (id: String?, error: String?) {
        var request: [String: Any] = ["op": "install", "name": name, "guest": guest]
        if let desktop { request["desktop"] = desktop }
        if let password { request["password"] = password }
        if let sizes {
            request["cores"] = sizes.cores
            request["memory_mb"] = sizes.memoryGB * 1024
            request["disk_gb"] = sizes.diskGB
        }
        if let file { request["file"] = file }
        if let qemu { request["qemu"] = qemu }
        if let pvgHost { request["pvg_host"] = pvgHost }
        let answer = await ask(request, timeout: .seconds(15))
        return (answer.machine, answer.error)
    }

    /// What the person chose at a failure: `try_again`, `choose_installer` or `open_without_driver`.
    func installChoose(machine: String, choice: String, path: String? = nil, password: String? = nil) async -> String? {
        var request: [String: Any] = ["op": "install_choose", "machine": machine, "choice": choice]
        if let password { request["password"] = password }
        if let path { request["path"] = path }
        return await ask(request).error
    }

    func installCancel(machine: String) async -> String? {
        await ask(["op": "install_cancel", "machine": machine]).error
    }

    /// Where one install stands, asked of the agent.
    func installStatus(machine: String) async -> InstallStatus? {
        await ask(["op": "install_status", "machine": machine]).installs?[machine]
    }

    func shareScreen(of machine: Machine, on: Bool, pairing: Bool = false, rmhost: String?) async -> String? {
        var request: [String: Any] = ["op": "share", "machine": machine.agentID, "on": on, "pairing": pairing]
        if let rmhost { request["rmhost"] = rmhost }
        return await ask(request).error
    }

    func shutDown(_ machine: Machine) async -> String? {
        await ask(["op": "shutdown", "machine": machine.agentID]).error
    }

    func forceOff(_ machine: Machine) async -> String? {
        await ask(["op": "force_off", "machine": machine.agentID]).error
    }

    /// A shutdown request nobody waits for, for quitting.
    func sendShutDownWithoutAnswer(_ machine: Machine) {
        nextID += 1
        link?.send(#"{"v":1,"id":\#(nextID),"op":"shutdown","machine":"\#(machine.agentID)"}"#)
    }

    // MARK: Connecting

    private func establish() async {
        var why: String?
        if AgentLauncher.preferLaunchd {
            switch AgentLauncher.registerWithLaunchd() {
            case .ready:
                if await adopt(XPCLink(onLine: lineHandler, onClose: closeHandler), route: String(localized: "launchd, over XPC")) {
                    return
                }
                why = String(localized: "launchd's agent did not answer")
            case .failed(let reason):
                why = reason
            }
            log.notice("Not using launchd: \(why ?? "", privacy: .public)")
        }
        let socket = Core.agentSocketPath
        if let socket, await adopt(SocketLink(path: socket, onLine: lineHandler, onClose: closeHandler), route: socketRoute(why)) {
            return
        }
        if let support = Core.supportFolder, let problem = AgentLauncher.startDetached(supportFolder: support) {
            route = problem
            return
        }
        // The agent needs a moment to open its socket.
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if let socket, await adopt(SocketLink(path: socket, onLine: lineHandler, onClose: closeHandler), route: socketRoute(why)) {
                return
            }
        }
        route = String(localized: "The agent did not start")
    }

    private func socketRoute(_ why: String?) -> String {
        let base = String(localized: "started by the app, over a Unix socket")
        return why.map { "\(base) (\($0))" } ?? base
    }

    /// Takes `link` if the agent answers a listing through it.
    private func adopt(_ candidate: (any AgentLink)?, route: String) async -> Bool {
        guard let candidate else { return false }
        link = candidate
        let answer = await ask(["op": "list"], timeout: .seconds(3))
        guard answer.ok, let listed = answer.statuses else {
            candidate.close()
            link = nil
            return false
        }
        statuses = listed.filter { $0.value != .off }
        shares = answer.shares ?? [:]
        installs = answer.installs ?? [:]
        if LaunchOptions.printStates {
            for (machine, install) in installs.sorted(by: { $0.key < $1.key }) { print(install.printLine()); _ = machine }
            print("connected: \(route)")
            for (machine, share) in shares.sorted(by: { $0.key < $1.key }) { print(share.printLine(machine: machine)) }
            for (machine, status) in statuses.sorted(by: { $0.key < $1.key }) {
                print("state: \(machine) \(status.state)\(status.reason.map { ": \($0)" } ?? "")")
            }
        }
        connected = true
        self.route = route
        onChange()
        return true
    }

    private var lineHandler: @Sendable (String) -> Void {
        { [weak self] line in Task { @MainActor in self?.receive(line) } }
    }

    private var closeHandler: @Sendable () -> Void {
        { [weak self] in Task { @MainActor in self?.lost() } }
    }

    private func lost() {
        guard connected else { return }
        connected = false
        route = String(localized: "Not connected")
        link?.close()
        link = nil
    }

    // MARK: Lines

    private func ask(_ fields: [String: Any], timeout: Duration = .seconds(5)) async -> AgentAnswer {
        guard let link else { return .failure(String(localized: "The agent is not running.")) }
        nextID += 1
        let id = nextID
        var request = fields
        request["v"] = 1
        request["id"] = id
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let line = String(data: data, encoding: .utf8)
        else { return .failure("Cannot write the request.") }
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            link.send(line)
            Task {
                try? await Task.sleep(for: timeout)
                if let late = pending.removeValue(forKey: id) {
                    late.resume(returning: .failure(String(localized: "The agent did not answer.")))
                }
            }
        }
    }

    private func receive(_ line: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        if object["event"] as? String == "install" {
            if let install = InstallStatus(json: object) {
                installs[install.machine] = install
                if LaunchOptions.printStates { print(install.printLine()) }
                onChange()
            }
            return
        }
        if object["event"] as? String == "share" {
            if let machine = object["machine"] as? String, let share = ShareStatus(json: object) {
                shares[machine] = share.state == .off ? nil : share
                if LaunchOptions.printStates { print(share.printLine(machine: machine)) }
                onChange()
            }
            return
        }
        if object["event"] as? String == "state" {
            if let machine = object["machine"] as? String, let status = Self.status(from: object) {
                statuses[machine] = status == .off ? nil : status
                if LaunchOptions.printStates {
                    print("state: \(machine) \(status.state)\(status.reason.map { ": \($0)" } ?? "")")
                }
                onChange()
            }
            return
        }
        guard let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) else { return }
        var listed: [String: MachineStatus]?
        if let machines = object["machines"] as? [[String: Any]] {
            listed = [:]
            for machine in machines {
                if let name = machine["machine"] as? String, let status = Self.status(from: machine) {
                    listed?[name] = status
                }
            }
        }
        var shared: [String: ShareStatus]?
        if let entries = object["shares"] as? [[String: Any]] {
            shared = [:]
            for entry in entries {
                if let name = entry["machine"] as? String, let share = ShareStatus(json: entry) {
                    shared?[name] = share
                }
            }
        }
        var installed: [String: InstallStatus]?
        if let entries = object["installs"] as? [[String: Any]] {
            installed = [:]
            for entry in entries {
                if let install = InstallStatus(json: entry) { installed?[install.machine] = install }
            }
        }
        continuation.resume(returning: AgentAnswer(
            ok: object["ok"] as? Bool ?? false,
            error: object["error"] as? String,
            statuses: listed,
            shares: shared,
            installs: installed,
            machine: object["machine"] as? String
        ))
    }

    private static func status(from object: [String: Any]) -> MachineStatus? {
        guard let state = object["state"] as? String else { return nil }
        return MachineStatus(
            state: state,
            reason: object["reason"] as? String
        )
    }
}
