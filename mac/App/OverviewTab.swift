// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The overview: the machine's screen as a picture with its name and buttons on it, and four
/// small facts under it.
struct OverviewTab: View {
    let machine: Machine
    @Environment(Library.self) private var library
    /// Read so the notice looks again when a QEMU is chosen in Settings.
    @AppStorage(SettingsKey.qemuPath) private var qemuSetting = ""

    var body: some View {
        VStack(spacing: 16) {
            if machine.startable, let sentence = library.startPlan(for: machine).problem {
                MissingQEMUNotice(sentence: sentence)
            }
            OverviewHero(machine: machine)
            FactCards(machine: machine)
        }
    }
}

/// Why Start is off when there is no QEMU, and the way to fix it.
struct MissingQEMUNotice: View {
    let sentence: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(sentence)
            Spacer()
            SettingsLink { Text("Open Settings") }
        }
        .card()
    }
}
