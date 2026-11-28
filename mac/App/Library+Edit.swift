import AppKit
import Foundation

/// Changing the library itself: renaming a machine and removing one.
extension Library {
    /// Renames `machine`; the reason is shown to the user when it cannot be.
    func rename(_ machine: Machine, to name: String) {
        if let problem = Core.rename(machine: machine.agentID, to: name) {
            requestProblem = problem
        }
        reload()
    }

    /// Whether `machine` can be removed: only one that is not running, since its disk is in use
    /// while it is.
    func canRemove(_ machine: Machine) -> Bool {
        !status(of: machine).isAlive
    }

    /// Moves the machine's folder to the Trash, so it can be got back until the Trash is
    /// emptied. Refuses a machine that is running, and any folder that is not directly inside
    /// the machines folder.
    func remove(_ machine: Machine) {
        guard canRemove(machine) else {
            requestProblem = String(localized: "\(machine.name) is running. Shut it down before removing it.")
            return
        }
        let folder = URL(filePath: machine.folder, directoryHint: .isDirectory).standardizedFileURL
        guard let root = Core.machinesFolder?.standardizedFileURL,
              folder.deletingLastPathComponent().path == root.path
        else {
            requestProblem = String(localized: "\(machine.name) is not in the machines folder, so Guesthouse leaves it alone.")
            return
        }
        do {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        } catch {
            requestProblem = String(localized: "Could not move \(machine.name) to the Trash: \(error.localizedDescription)")
        }
        reload()
        if !machines.contains(where: { $0.id == selection }) { selection = machines.first?.id }
    }
}

/// Showing a machine's screen to other devices.
extension Library {
    /// Allows or forbids it. A running machine starts or stops sharing at once; a stopped one
    /// shares when it next runs.
    func setRemoteView(_ machine: Machine, allowed: Bool) {
        if let problem = Core.setRemoteView(machine: machine.agentID, on: allowed) {
            requestProblem = problem
            return
        }
        reload()
        guard status(of: machine).state == "running" else { return }
        let rmhost = self.rmhost.path
        run { await self.agent.shareScreen(of: machine, on: allowed, rmhost: rmhost) }
    }

    /// Opens pairing for the next new device, for a short time. The agent closes it again.
    func pairNewDevice(_ machine: Machine) {
        let rmhost = self.rmhost.path
        run { await self.agent.shareScreen(of: machine, on: true, pairing: true, rmhost: rmhost) }
    }
}

/// Answering a device that waits to be paired, and ending a pairing that is open.
extension Library {
    func acceptDevice(_ machine: Machine) {
        run { await self.agent.pair("pair_accept", machine: machine) }
    }

    func declineDevice(_ machine: Machine) {
        run { await self.agent.pair("pair_decline", machine: machine) }
    }

    func stopPairing(_ machine: Machine) {
        run { await self.agent.pair("pair_close", machine: machine) }
    }
}

/// The devices that can view a machine.
extension Library {
    func setControl(_ machine: Machine, device: ShareStatus.Device, allowed: Bool) {
        run { await self.agent.deviceAllow(machine: machine, fingerprint: device.fingerprint, what: "input", on: allowed) }
    }

    func removeDevice(_ machine: Machine, device: ShareStatus.Device) {
        run { await self.agent.deviceRemove(machine: machine, fingerprint: device.fingerprint) }
    }

    func disconnectDevice(_ machine: Machine) {
        run { await self.agent.deviceDisconnect(machine: machine) }
    }
}
