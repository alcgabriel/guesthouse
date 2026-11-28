import Foundation
import GuesthouseCore

/// What the New Machine sheet asks for. The core checks it and makes the machine.
nonisolated struct NewMachineRequest: Encodable, Equatable {
    var name = ""
    var cores = 4
    var memoryMB = 6144
    var disk = ""
    var firmwareCode = ""
    var firmwareVars = ""
    var optionROM = ""
    /// The Mac's own size, for the core's limits.
    var hostMemoryMB = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
    var hostCores = ProcessInfo.processInfo.activeProcessorCount

    enum CodingKeys: String, CodingKey {
        case name, cores, disk
        case memoryMB = "memory_mb"
        case firmwareCode = "firmware_code"
        case firmwareVars = "firmware_vars"
        case optionROM = "option_rom"
        case hostMemoryMB = "host_memory_mb"
        case hostCores = "host_cores"
    }

    /// An option ROM that is left empty is not sent at all.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(cores, forKey: .cores)
        try container.encode(memoryMB, forKey: .memoryMB)
        try container.encode(disk, forKey: .disk)
        try container.encode(firmwareCode, forKey: .firmwareCode)
        try container.encode(firmwareVars, forKey: .firmwareVars)
        if !optionROM.isEmpty { try container.encode(optionROM, forKey: .optionROM) }
        try container.encode(hostMemoryMB, forKey: .hostMemoryMB)
        try container.encode(hostCores, forKey: .hostCores)
    }
}

nonisolated extension Core {
    /// Everything wrong with `request`, in plain sentences; empty when it can be made.
    static func problems(with request: NewMachineRequest) -> [String] {
        answer(of: guesthouse_machine_check, for: request).problems ?? []
    }

    /// Makes the machine and returns its folder name, or the problems that stopped it. Copying a
    /// large disk that cannot be cloned takes a while: call this off the main thread.
    static func create(_ request: NewMachineRequest) -> Result<String, MachineProblems> {
        let reply = answer(of: guesthouse_machine_create, for: request)
        if let id = reply.id { return .success(id) }
        return .failure(MachineProblems(problems: reply.problems ?? [reply.error ?? "The core gave no answer."]))
    }

    /// Gives the machine in folder `id` another name; nil when it worked, else the reason.
    static func rename(machine id: String, to name: String) -> String? {
        guard let text = guesthouse_machine_rename(id, name) else { return "The core gave no answer." }
        defer { guesthouse_string_free(text) }
        let reply = try? JSONDecoder().decode(Reply.self, from: Data(String(cString: text).utf8))
        return reply?.error
    }

    /// Allows or forbids viewing the machine in folder `id` from other devices; nil when it
    /// worked, else the reason. Nothing listens until the machine runs and the agent shares it.
    static func setRemoteView(machine id: String, on: Bool) -> String? {
        guard let text = guesthouse_machine_set_remote_view(id, on) else { return "The core gave no answer." }
        defer { guesthouse_string_free(text) }
        return (try? JSONDecoder().decode(Reply.self, from: Data(String(cString: text).utf8)))?.error
    }

    /// Changes a stopped machine's processors and memory; the problems that stopped it, if any.
    static func setHardware(machine id: String, cores: Int, memoryMB: Int) -> [String] {
        let request: [String: Int] = [
            "cores": cores, "memory_mb": memoryMB,
            "host_cores": ProcessInfo.processInfo.activeProcessorCount,
            "host_memory_mb": Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let json = String(data: data, encoding: .utf8),
              let text = guesthouse_machine_set_hardware(id, json)
        else { return ["The core gave no answer."] }
        defer { guesthouse_string_free(text) }
        let reply = try? JSONDecoder().decode(Reply.self, from: Data(String(cString: text).utf8))
        return reply?.problems ?? (reply?.error).map { [$0] } ?? []
    }

    /// Moves the machine's graphics device (`guarded` or `qemu`); nil when it worked, else why.
    static func setGraphics(machine id: String, to graphics: String) -> String? {
        guard let text = guesthouse_machine_set_graphics(id, graphics) else { return "The core gave no answer." }
        defer { guesthouse_string_free(text) }
        return (try? JSONDecoder().decode(Reply.self, from: Data(String(cString: text).utf8)))?.error
    }

    /// The graphics process's own counts, or nil when it is not there.
    static func graphicsStatus(machine id: String) -> GraphicsCounts? {
        guard let text = guesthouse_graphics_status(id) else { return nil }
        defer { guesthouse_string_free(text) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any],
              object["error"] == nil
        else { return nil }
        return GraphicsCounts(
            published: object["published"] as? Int ?? 0,
            refused: object["refused"] as? Int ?? 0,
            spoiled: object["spoiled"] as? Bool ?? false)
    }

    private struct Reply: Decodable {
        var id: String?
        var problems: [String]?
        var error: String?
    }

    private static func answer(of function: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?, for request: NewMachineRequest) -> Reply {
        guard let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8),
              let text = function(json)
        else { return Reply(error: "The core gave no answer.") }
        defer { guesthouse_string_free(text) }
        return (try? JSONDecoder().decode(Reply.self, from: Data(String(cString: text).utf8)))
            ?? Reply(error: "The core's answer could not be read.")
    }
}

/// Why a machine could not be made.
nonisolated struct MachineProblems: Error {
    let problems: [String]
}

extension Core {
    /// Tells the core the screen size that would fill the machine's window. Today the core only
    /// records it (see `core/src/screen_size.rs`); returns why it refused, if it did.
    @discardableResult
    static func setWantedScreen(machine id: String, _ wanted: WantedScreen) -> String? {
        guard let text = guesthouse_machine_set_wanted_screen(
            id, UInt32(wanted.pixelsWidth), UInt32(wanted.pixelsHeight), UInt32(wanted.scalingPercent))
        else { return "The core gave no answer." }
        defer { guesthouse_string_free(text) }
        return (try? JSONDecoder().decode(Reply.self, from: Data(String(cString: text).utf8)))?.error
    }
}
