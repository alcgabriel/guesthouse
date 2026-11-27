// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Viewing the machine's screen from other devices with remoteman: the switch, pairing, how to
/// connect, and the devices that can.
struct SharingTab: View {
    let machine: Machine
    @Environment(Library.self) private var library

    private var share: ShareStatus { library.agent.share(of: machine) }
    private var running: Bool { library.status(of: machine).state == "running" }

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                AllowViewingCard(machine: machine).gridCellColumns(12)
            }
            if machine.remoteView, running, share.state == .listening, let port = share.port {
                GridRow {
                    PairingCard(machine: machine, share: share).gridCellColumns(7)
                    ConnectCard(machine: machine, share: share, port: port).gridCellColumns(5)
                }
                GridRow {
                    DevicesCard(machine: machine, share: share).gridCellColumns(12)
                }
                GridRow {
                    Text("Only devices you accepted here can connect. Anyone on the same network can ask to pair while pairing is open.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .gridCellColumns(12)
                        .gridColumnAlignment(.leading)
                }
            }
        }
    }
}
