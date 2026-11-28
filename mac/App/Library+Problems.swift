import AppKit
import Foundation
import GuesthouseCore
import Metal

extension Library {
    /// Asks to show `machine`'s page on `tab`, for a message that sends the person there.
    func show(_ machine: Machine, tab: MachineTab) {
        selection = machine.id
        tabRequest = tab
    }

    /// Opens the bug report sheet for `machine` (or the app), as the same one everywhere: Details,
    /// the install that stopped and the problem messages. A message that is up is put away first.
    func report(machine: Machine?, kind: ReportKind) {
        attention = nil
        reporting = ReportStart(machineID: machine?.id, kind: kind)
    }

    /// What Start would run into for want of memory, if anything: against what the other machines
    /// that run hold, and against what is free now. The core judges; this reads the Mac.
    func memoryProblem(starting machine: Machine) -> Problem? {
        let running = machines.filter { $0.id != machine.id && status(of: $0).isAlive }
        let held = Problem.from(core: Core.startCheck([
            "check": "memory", "machine": machine.name, "wanted_mb": machine.memoryMB, "host_mb": ThisMac.memoryMB,
            "running": running.map { ["name": $0.name, "memory_mb": $0.memoryMB] },
        ]))
        if let held { return held }
        return Problem.from(core: Core.startCheck([
            "check": "memory_now", "machine": machine.name, "wanted_mb": machine.memoryMB,
            "available_mb": ThisMac.availableMB as Any? ?? NSNull(),
            "running_mb": running.reduce(0) { $0 + $1.memoryMB },
        ]))
    }

    /// What Start would run into for want of disk: the disk can grow to its whole size.
    func diskProblem(starting machine: Machine) -> Problem? {
        guard let usage = DiskUsage.read(path: machine.disk) else { return nil }
        let folder = URL(filePath: machine.folder)
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Problem.from(core: Core.startCheck([
            "check": "disk", "machine": machine.name, "size_bytes": usage.size, "on_disk_bytes": usage.onDisk,
            "free_bytes": free,
        ]))
    }

    /// Whether the graphics driver in the machine is old or missing, when the core can tell (it
    /// says nothing when the version the machine reported or the released one is not known).
    func driverProblem(starting machine: Machine) -> Problem? {
        guard let text = guesthouse_driver_state(machine.agentID) else { return nil }
        defer { guesthouse_string_free(text) }
        return Problem.driver(json: String(cString: text), machine: machine.name, machineID: machine.id)
    }

    /// The first problem Start would run into, unless the person has said to go on without it.
    func startProblem(for machine: Machine, ignoring: Set<StartCheck>) -> Problem? {
        for name in Rules.startCheckOrder {
            switch name {
            case "memory" where !ignoring.contains(.memory):
                if let found = memoryProblem(starting: machine) { return found }
            case "disk" where !ignoring.contains(.disk):
                if let found = diskProblem(starting: machine) { return found }
            case "driver" where !ignoring.contains(.driver):
                if let found = driverProblem(starting: machine) { return found }
            default: break
            }
        }
        return nil
    }

    /// Called when the agent says something changed: a machine that was started here and has
    /// now failed gets its message, once.
    func watchStarts() {
        for machine in machines where startedHere.contains(machine.agentID) {
            let state = status(of: machine).state
            if state == "failed" {
                startedHere.remove(machine.agentID)
                attention = .didNotStart(machine: machine.name, machineID: machine.id)
            } else if state == "running" {
                startedHere.remove(machine.agentID)
            }
        }
    }

    /// Whether this Mac can draw a machine with its GPU: Apple silicon and a Metal device. The
    /// app needs macOS 27 to open at all, so the system's version is not asked here.
    static func gpuProblem() -> Problem? {
        #if arch(arm64)
        if MTLCreateSystemDefaultDevice() != nil { return nil }
        return .noGPU(has: String(localized: "no GPU that Metal can use"))
        #else
        return .noGPU(has: String(localized: "an Intel processor"))
        #endif
    }

    /// Asks every running machine to power off, then quits without asking what to do.
    func quitShuttingDown() {
        for machine in machines where status(of: machine).state == "running" {
            agent.sendShutDownWithoutAnswer(machine)
        }
        quitShutsDown = true
        NSApp.terminate(nil)
    }
}
