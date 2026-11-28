// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The switch, and one sentence on where sharing stands.
struct AllowViewingCard: View {
    let machine: Machine
    @Environment(Library.self) private var library

    private var status: MachineStatus { library.status(of: machine) }
    private var share: ShareStatus { library.agent.share(of: machine) }
    private var rmhost: ToolLocation { library.rmhost }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Allow viewing from other devices")
                    .font(.headline)
                Text(sentence)
                    .foregroundStyle(share.state == .failed && machine.remoteView ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if machine.remoteView {
                    Text(ShareStatus.networkWarning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("Allow viewing from other devices", isOn: allowed)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!canChange)
        }
        .card(padding: 16)
    }

    private var allowed: Binding<Bool> {
        Binding(get: { machine.remoteView }, set: { library.setRemoteView(machine, allowed: $0) })
    }

    /// Turning it off is always possible; turning it on needs a program to do the sharing and
    /// a machine the app runs.
    private var canChange: Bool {
        machine.remoteView || (machine.startable && rmhost.path != nil)
    }

    private var sentence: String {
        if !machine.startable {
            return String(localized: "Only machines that Guesthouse starts can be viewed from another device.")
        }
        if case .missing(let missing) = rmhost, !machine.remoteView { return missing }
        return ShareStatus.headline(allowed: machine.remoteView, machineRunning: status.state == "running", share: share)
    }
}
