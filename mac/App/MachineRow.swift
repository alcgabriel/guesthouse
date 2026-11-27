// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// A machine in the sidebar: a plain mark for its system, its name and where it stands.
struct MachineRow: View {
    let machine: Machine
    let status: MachineStatus
    @Environment(Library.self) private var library

    /// Set while the machine's install is going on or has stopped.
    private var install: InstallStatus? {
        library.showsInstall(machine) ? library.install(of: machine) : nil
    }

    var body: some View {
        HStack(spacing: 10) {
            MachineMark(kind: machine.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let install {
                        Text(install.sidebarLine).font(.caption).foregroundStyle(.secondary)
                    } else {
                        StateDot(color: status.color, size: 7)
                        Text(status.plainTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(machine.name)
        .accessibilityValue(status.plainTitle)
    }
}

/// The same neutral mark for every machine of a system: a window for Windows, a terminal for the
/// rest. It is not the machine's picture, which would flicker in a list and cost a reader.
struct MachineMark: View {
    let kind: String

    var body: some View {
        Image(systemName: kind == "windows" ? "macwindow" : "terminal")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}
