import SwiftUI

/// The overview's picture: the machine's screen filling the card, live while it runs, with its
/// name, how it stands and the two buttons over a dark fade at the bottom.
struct OverviewHero: View {
    let machine: Machine
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow

    /// A few times a second is enough to see what the machine is doing without working the device.
    private static let refreshInterval: TimeInterval = 0.2
    /// The card keeps a 16:10 shape, within these heights, so the facts under it stay in view.
    private static let aspect: CGFloat = 1.6
    private static let leastHeight: CGFloat = 260
    private static let mostHeight: CGFloat = 520

    private var status: MachineStatus { library.status(of: machine) }

    var body: some View {
        ZStack(alignment: .bottom) {
            picture
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .init(x: 0.5, y: 0.35), endPoint: .bottom)
                .allowsHitTesting(false)
            caption
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .frame(minHeight: Self.leastHeight, maxHeight: Self.mostHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var picture: some View {
        ZStack {
            Color(red: 0.055, green: 0.1, blue: 0.17)
            if status.isAlive, let session = library.screenSession(for: machine) {
                PictureViewRepresentable(session: session, interval: Self.refreshInterval)
                    .onTapGesture { openScreen() }
                    .help("Open the screen in a window")
            } else {
                Image(systemName: "display")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
                    .accessibilityHidden(true)
            }
        }
    }

    private var caption: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    StateDot(color: status.color)
                    Text(status.title).fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(.black.opacity(0.6), in: Capsule())
                Text(machine.name).font(.title.weight(.semibold))
                Text(subtitle).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            buttons
        }
        .foregroundStyle(.white)
        .padding(24)
    }

    /// What the machine is, and for one that is not simply on or off, what has happened.
    private var subtitle: String {
        switch status.state {
        case "running", "stopped": MachineFormat.kindDescription(machine.kind)
        default: status.sentence(for: machine.name)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if status.nextStep == .forceOff {
            Button("Force Off") { library.forceOff(machine) }
        }
        if status.state == "running" {
            Button("Shut Down") { library.shutDown(machine) }
        } else if status.nextStep == .start, machine.startable {
            Button("Start") { library.start(machine) }
                .disabled(!library.agent.connected || library.startPlan(for: machine).problem != nil)
        }
        if machine.frames != nil, status.isAlive || !machine.startable {
            Button("Open Screen", action: openScreen)
                .buttonStyle(.borderedProminent)
        }
    }

    private func openScreen() {
        openWindow(id: ScreenWindow.windowID, value: machine.id)
    }
}
