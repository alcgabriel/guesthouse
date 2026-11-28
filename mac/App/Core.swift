import Foundation
import GuesthouseCore

/// One machine, as the core lists it.
nonisolated struct Machine: Decodable, Identifiable, Hashable {
    /// The machine's folder name: how the agent names it.
    let agentID: String
    let name: String
    let kind: String
    let cores: Int
    let memoryMB: Int
    let disk: String
    /// The bootstrap name the machine's screen is published under, if any.
    let frames: String?
    /// The QMP socket that takes the machine's input, if any.
    let qmp: String?
    let state: String
    let folder: String
    /// Whether the agent can start it: its machine.json names the firmware files.
    let startable: Bool
    /// The display modes the device offers, as `1024x768@60`, the first being the one it
    /// starts in. Empty when the app does not start the machine.
    let modes: [String]
    /// Whether the person allowed other devices to view this machine's screen.
    let remoteView: Bool
    /// Where the graphics device lives: `guarded` (its own process) or `qemu` (QEMU's own).
    let graphics: String
    /// The port the screen is shared on, once one has been chosen.
    let remotePort: Int?

    var id: String { folder }

    enum CodingKeys: String, CodingKey {
        case name, kind, cores, disk, frames, qmp, state, folder, startable, modes
        case remoteView = "remote_view"
        case graphics
        case remotePort = "remote_port"
        case agentID = "id"
        case memoryMB = "memory_mb"
    }
}

/// A folder in the machines folder that the core could not read as a machine.
nonisolated struct SkippedFolder: Decodable {
    let folder: String
    let reason: String
}

nonisolated struct CoreError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The Rust core's C interface, in Swift types.
nonisolated enum Core {
    static var version: String {
        String(cString: guesthouse_core_version())
    }

    /// The agent's Unix socket, in the support folder.
    static var agentSocketPath: String? {
        guard let text = guesthouse_agent_socket_path() else { return nil }
        defer { guesthouse_string_free(text) }
        return String(cString: text)
    }

    /// The folder the app keeps its machines, run folders and the agent's socket in.
    static var supportFolder: URL? {
        agentSocketPath.map { URL(filePath: $0).deletingLastPathComponent() }
    }

    static var machinesFolder: URL? {
        guard let text = guesthouse_machines_folder() else { return nil }
        defer { guesthouse_string_free(text) }
        return URL(filePath: String(cString: text), directoryHint: .isDirectory)
    }

    /// The machines in the default machines folder, and the folders that could not be read.
    static func listMachines() throws -> (machines: [Machine], skipped: [SkippedFolder]) {
        guard let text = guesthouse_machine_list(nil) else {
            throw CoreError(message: "The core gave no answer.")
        }
        defer { guesthouse_string_free(text) }
        let answer = try JSONDecoder().decode(ListAnswer.self, from: Data(String(cString: text).utf8))
        if let error = answer.error {
            throw CoreError(message: error)
        }
        return (answer.machines ?? [], answer.skipped ?? [])
    }

    /// Either a listing or an error, as `guesthouse_machine_list` answers.
    private struct ListAnswer: Decodable {
        let machines: [Machine]?
        let skipped: [SkippedFolder]?
        let error: String?
    }
}
