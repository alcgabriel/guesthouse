import AppKit
import SwiftUI

/// What a person types into remoteman on the other device: the name, the address and the
/// fingerprint to compare.
struct ConnectCard: View {
    let machine: Machine
    let share: ShareStatus
    let port: Int
    @Environment(Library.self) private var library

    private var address: String { "\(LocalNetwork.address ?? LocalNetwork.hostName):\(port)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Connect from remoteman")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                row("Name", Text(machine.name))
                row("Address", Text(address).font(.system(.callout, design: .monospaced)).textSelection(.enabled))
                if LocalNetwork.address != nil {
                    row("or", Text("\(LocalNetwork.hostName):\(port)").font(.system(.callout, design: .monospaced)).textSelection(.enabled))
                }
                if let short = share.shortFingerprint {
                    row("Fingerprint", Text(short)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .help(share.fingerprint ?? ""))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }
                .frame(maxWidth: .infinity)
                Button("Pair a New Device") { library.pairNewDevice(machine) }
                    .frame(maxWidth: .infinity)
                    .disabled(share.pairing || share.pending != nil)
            }
        }
        .card(padding: 18, fillsHeight: true)
    }

    private func row(_ title: LocalizedStringKey, _ value: some View) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            value.gridColumnAlignment(.trailing)
        }
    }
}
