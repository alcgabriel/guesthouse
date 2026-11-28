import Foundation

extension Library {
    /// The install the agent knows for `machine`, if there is one.
    func install(of machine: Machine) -> InstallStatus? {
        agent.installs[machine.agentID]
    }

    /// Whether the machine's pane shows the install screens instead of the tabs: while it runs or
    /// has stopped, and once when it is done. A stopped (cancelled) install is an ordinary machine.
    func showsInstall(_ machine: Machine) -> Bool {
        guard let install = install(of: machine) else { return false }
        return Rules.showsInstall(installState: install.state, seen: installsSeen.contains(machine.agentID))
    }

    func markInstallSeen(_ machine: Machine) {
        installsSeen.insert(machine.agentID)
        UserDefaults.standard.set(Array(installsSeen).sorted(), forKey: SettingsKey.installsSeen)
    }

    /// The agent has an install the list does not show yet (it makes the machine as it starts),
    /// so look again.
    func syncInstalls() {
        let known = Set(machines.map(\.agentID))
        if agent.installs.keys.contains(where: { !known.contains($0) }) { reload() }
    }

    /// An install that stopped for want of its password (a new agent took it up) is put right
    /// without the person doing anything: the app has the password in the Keychain and gives it
    /// again with Try Again. Once for each stop, so a machine whose password is not in the
    /// Keychain is left stopped, with its message, for the person.
    func repairInstalls() {
        for (id, install) in agent.installs where install.needsPassword && !repairing.contains(id) {
            repairing.insert(id)
            guard let password = PasswordKeychain.read(for: id) else { continue }
            Task {
                _ = await agent.installChoose(machine: id, choice: "try_again", password: password)
                repairing.remove(id)
            }
        }
        // A stop that has gone is forgotten, so the next one is repaired too.
        repairing = repairing.filter { agent.installs[$0]?.needsPassword == true }
    }

    /// Starts an install and selects the machine it makes. Returns why it did not start.
    func startInstall(
        guest: InstallGuest, name: String, file: String?, sizes: InstallSizes?, desktop: String? = nil
    ) async -> String? {
        let plan = startPlan(forInstall: ())
        // Made here and kept in the Keychain at once, under a token, because the machine's own id
        // is only known when the agent answers.
        let password = GuestPassword.generate()
        let token = "new-" + UUID().uuidString
        guard PasswordKeychain.save(password, for: token, label: name) else {
            return String(localized: "The password for the new machine could not be kept in the Keychain.")
        }
        let result = await agent.install(
            name: name, guest: guest.rawValue, file: file, qemu: plan.qemu, pvgHost: plan.pvgHost,
            sizes: sizes, password: password, desktop: desktop)
        if let error = result.error {
            PasswordKeychain.delete(for: token)
            return error
        }
        if let id = result.id {
            PasswordKeychain.save(password, for: id, label: name)
        }
        PasswordKeychain.delete(for: token)
        reload()
        if let id = result.id, let machine = machines.first(where: { $0.agentID == id }) {
            selection = machine.id
        }
        return nil
    }

    /// The room the Mac has for a new machine, in whole gigabytes, if it can be read.
    static func freeSpaceGB() -> Int? {
        // The stand-in install makes nothing big, so the agent does not check for room, and the
        // sheet does not either.
        if ProcessInfo.processInfo.environment["GUESTHOUSE_INSTALL_FAKE"] != nil { return nil }
        let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { InstallText.gigabytes($0) }
    }
}
