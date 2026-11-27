// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Pairing a new device: closed, open with the time left, or a device waiting with its code
/// and Accept and Decline.
struct PairingCard: View {
    let machine: Machine
    let share: ShareStatus
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardTitle(verbatim: Wording.text("remote_view.pairing_title"))
                Spacer()
                header
            }
            if let device = share.pending {
                waiting(device)
            } else if share.pairing {
                open
            } else {
                closed
            }
        }
        .card(highlighted: share.pending != nil, padding: 18, fillsHeight: true)
    }

    /// The right of the title: what the card is waiting for, with the time left.
    @ViewBuilder
    private var header: some View {
        if let device = share.pending {
            HStack(spacing: 4) {
                Text(Wording.text("remote_view.waiting_time_left"))
                Text(timerInterval: Date.now...device.until, countsDown: true).monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if share.pairing, let until = share.pairingUntil, until > .now {
            HStack(spacing: 4) {
                Text(Wording.text("remote_view.open_time_left"))
                Text(timerInterval: Date.now...until, countsDown: true).monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func waiting(_ device: ShareStatus.Pending) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Wording.text("remote_view.wants_to_pair", ["name": device.name]))
                        .font(.title3.weight(.semibold))
                    Text(ShareStatus.compareCodeLine)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(device.code)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                    .textSelection(.enabled)
                    .accessibilityLabel(Wording.text("remote_view.code_label", ["code": device.code]))
            }
            HStack {
                Spacer()
                Button(Wording.text("remote_view.decline")) { library.declineDevice(machine) }
                Button(Wording.text("remote_view.accept")) { library.acceptDevice(machine) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var open: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ShareStatus.pairingSteps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(Wording.text("remote_view.stop")) { library.stopPairing(machine) }
            }
        }
        .foregroundStyle(.secondary)
    }

    private var closed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(share.closedText)
            Text(ShareStatus.pairedHint)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
