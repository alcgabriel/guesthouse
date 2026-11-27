// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The four small cards under the overview's picture: what draws the machine, its screen, its
/// size and the other devices. Each is a title, a line of value and a line of detail.
struct FactCards: View {
    let machine: Machine
    @Environment(Library.self) private var library
    @State private var usage: DiskUsage?

    private static let leastCardWidth: CGFloat = 170

    private var status: MachineStatus { library.status(of: machine) }

    var body: some View {
        // Four across when there is room, two by two when there is not.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.leastCardWidth), spacing: 12, alignment: .top)], spacing: 12) {
            fact("Graphics", value: graphicsValue, note: graphicsNote)
            fact("Screen", value: screenValue, note: screenNote)
            fact("Size", value: sizeValue, note: diskNote)
            fact("Other devices", value: devicesValue, note: devicesNote)
        }
        .task(id: machine.disk) { usage = DiskUsage.read(path: machine.disk) }
    }

    private func fact(_ title: LocalizedStringKey, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardTitle(title)
            Text(value).font(.headline).lineLimit(1)
            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(4)
        }
        .card(padding: 16, fillsHeight: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: Graphics

    private var graphicsValue: String {
        machine.graphics == "qemu" ? String(localized: "QEMU's own device") : String(localized: "This Mac's GPU")
    }

    private var graphicsNote: String {
        if let warning = library.graphics[machine.agentID]?.warning(system: MachineFormat.systemName(machine.kind)) {
            return warning
        }
        return machine.graphics == "qemu"
            ? String(localized: "Without the guard that protects this Mac")
            : String(localized: "Behind a guard that protects this Mac")
    }

    // MARK: Screen

    /// Whether the machine's screen follows its window: on the protected path, with the Hardware
    /// tab's switch on. QEMU's own device takes no size.
    private var follows: Bool {
        machine.graphics != "qemu" && ScreenPrefs.follows(machine.id)
    }

    private var screenValue: String {
        follows ? String(localized: "Follows its window") : String(localized: "A fixed size")
    }

    private var screenNote: String {
        if status.isAlive, let session = library.screens[machine.id], let size = session.pictureSize {
            return String(localized: "Now \(String(size.width)) × \(String(size.height)), \(ScreenStatus.rateText(framesPerSecond: session.receivedPerSecond)).")
        }
        let parts = MachineFormat.modeParts(machine.modes.first ?? "")
        let mode = parts.map { "\($0.size), \($0.rate)" } ?? String(localized: "Shown when it runs")
        return follows ? String(localized: "Starts at \(mode), then takes its window's size.") : mode + "."
    }

    // MARK: Size

    private var sizeValue: String {
        String(localized: "\(machine.cores) processors, \(MachineFormat.memory(megabytes: machine.memoryMB))")
    }

    private var diskNote: String {
        guard let usage else { return String(localized: "The disk image is not there") }
        return String(localized: "\(MachineFormat.fileSize(usage.onDisk)) of its \(MachineFormat.fileSize(usage.size)) disk used")
    }

    // MARK: Other devices

    private var share: ShareStatus { library.agent.share(of: machine) }

    private var devicesValue: String {
        guard machine.remoteView else { return String(localized: "Not shared") }
        if let viewer = share.viewer { return String(localized: "\(viewer) is viewing") }
        return share.state == .listening ? String(localized: "None viewing") : String(localized: "Not shared yet")
    }

    private var devicesNote: String {
        let count = share.devices.count
        return count == 0 ? String(localized: "No devices paired") : String(localized: "\(count) devices paired")
    }
}
