import SwiftUI

/// What the library shows before there is a machine: the one choice, Windows or Ubuntu, and a
/// small link for a person who brings their own disk or installer.
struct WelcomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "house.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(.tint, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Choose what it will run")
                    .font(.largeTitle.weight(.semibold))
                Text("Guesthouse installs the system and sets up graphics on this Mac's GPU. It downloads Ubuntu for you; for Windows you bring the installer you got from Microsoft. You don't have to do anything in between.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            HStack(spacing: 16) {
                GuestChoice(guest: .windows, prominent: true, symbol: "macwindow",
                            text: "Windows 11 with the GPU. You bring the installer file.")
                GuestChoice(guest: .ubuntu, prominent: false, symbol: "terminal",
                            text: "Downloaded and installed for you, with the GPU.")
            }
            .frame(maxWidth: 640)
            Button("I already have a disk or an installer") { library.showingNewMachine = true }
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One of the two big choices.
private struct GuestChoice: View {
    let guest: InstallGuest
    let prominent: Bool
    let symbol: String
    let text: LocalizedStringKey
    @Environment(Library.self) private var library

    var body: some View {
        Button { library.installing = guest } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 26))
                Text(guest.shortName).font(.headline)
                Text(text)
                    .foregroundStyle(prominent ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(prominent ? 0 : 0.1))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(guest.shortName)
    }
}
