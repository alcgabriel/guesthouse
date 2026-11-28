import SwiftUI

/// The devices that can view this machine, with control switched per device, Disconnect for the
/// one connected and Remove for a device that is not. The host serves video and input, so
/// clipboard, files and sound have no switch here.
struct DevicesCard: View {
    let machine: Machine
    let share: ShareStatus
    @Environment(Library.self) private var library
    @State private var removing: ShareStatus.Device?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Devices that can view this machine")
                Spacer()
                Text("Control").frame(width: 90)
                Text("").frame(width: 190)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if share.devices.isEmpty {
                Divider()
                Text("No device has been paired yet. Press Pair a New Device to add one.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(share.devices) { device in
                Divider()
                row(device)
            }
        }
        .card(padding: 0)
        .confirmationDialog(
            "Remove \(removing?.name ?? "this device")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let removing { library.removeDevice(machine, device: removing) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("It will be disconnected and will have to be paired again to view this machine.")
        }
    }

    private func row(_ device: ShareStatus.Device) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).fontWeight(.semibold)
                HStack(spacing: 5) {
                    StateDot(color: device.connected ? .green : .gray, size: 7)
                    Text(device.statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Control for \(device.name)", isOn: Binding(
                get: { device.control },
                set: { library.setControl(machine, device: device, allowed: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(width: 90)
            HStack {
                Spacer()
                if device.connected {
                    Button("Disconnect") { library.disconnectDevice(machine) }
                }
                Button("Remove", role: .destructive) { removing = device }
                    .foregroundStyle(.red)
            }
            .frame(width: 190)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}
