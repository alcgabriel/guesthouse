import AppKit
import SwiftUI

/// A machine's screen window, one per machine, named by the machine's folder.
struct ScreenWindow: View {
    static let windowID = "screen"

    let machineID: String
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if let machine = library.machines.first(where: { $0.id == machineID }), machine.frames != nil {
                ScreenContent(machine: machine)
                    .id(machineID)
            } else {
                ContentUnavailableView("No Screen", systemImage: "display.trianglebadge.exclamationmark")
            }
        }
        .onAppear {
            // A window brought back at launch may open before the library has looked.
            if library.machines.isEmpty { library.reload() }
        }
    }
}

/// The picture filling the window under a normal title bar, with the machine's state in the title,
/// the keyboard hint, Send Keys, full screen and Shut Down in the toolbar. Nothing else takes room
/// from the picture: no footer, no bars.
private struct ScreenContent: View {
    let machine: Machine
    @State private var session: ScreenSession
    @Environment(Library.self) private var library
    @AppStorage(SettingsKey.showScreenStatistics) private var showStatistics = false
    @AppStorage private var follows: Bool
    @AppStorage private var sharp: Bool
    /// The size the window's picture area last settled at, in points.
    @State private var settled: CGSize?

    init(machine: Machine) {
        self.machine = machine
        // The session is the machine's one; a preview may be using it already.
        _session = State(initialValue: Library.shared.screenSession(for: machine)
            ?? ScreenSession(machine: machine, service: ""))
        _follows = AppStorage(wrappedValue: true, ScreenPrefs.followsKey(machine.id))
        _sharp = AppStorage(wrappedValue: true, ScreenPrefs.sharpKey(machine.id))
    }

    private var status: MachineStatus { library.status(of: machine) }
    private var share: ShareStatus { library.agent.share(of: machine) }

    var body: some View {
        ScreenViewRepresentable(session: session, onSizeSettled: sizeSettled, stamp: (follows ? 1 : 0) + (sharp ? 2 : 0))
            .overlay {
                if session.state == .waiting {
                    Text(session.refusedReason ?? String(localized: "No picture yet"))
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .overlay(alignment: .topLeading) {
                if showStatistics { ScreenStatisticsOverlay(session: session) }
            }
            .overlay(alignment: .bottomTrailing) {
                if share.state == .listening, let viewer = share.viewer {
                    ViewerPill(text: String(localized: "\(viewer) is viewing"))
                }
            }
            .frame(minWidth: 320, minHeight: 180)
            .navigationTitle(machine.name)
            .navigationSubtitle(subtitle)
            .toolbar { ScreenToolbar(machine: machine, session: session) }
    }

    /// "Running · 1180 × 696": the state, and the window's size when the screen follows it.
    private var subtitle: String {
        guard follows, let settled else { return status.title }
        return status.title + " · " + "\(Int(settled.width)) × \(Int(settled.height))"
    }

    /// A resize ended: work out the screen that fills the window and give it to the core.
    private func sizeSettled(_ points: CGSize) {
        settled = points
        guard follows else { return }
        // A display that is not Retina has no pixels to spare, so Sharp is Standard there.
        let retina = (NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) >= 2
        let wanted = WantedScreen.wanted(points: points, sharp: sharp && retina)
        if let problem = Core.setWantedScreen(machine: machine.agentID, wanted) {
            print("guesthouse: the screen size was not taken: \(problem)")
        }
    }
}

/// "Phone is viewing", over the picture's bottom right corner.
private struct ViewerPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            StateDot(color: .green, size: 7)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.black.opacity(0.82), in: Capsule())
        .padding(12)
    }
}

/// The toolbar: whether the keyboard is in the machine, Send Keys, full screen and Shut Down.
private struct ScreenToolbar: ToolbarContent {
    let machine: Machine
    let session: ScreenSession
    @Environment(Library.self) private var library

    var body: some ToolbarContent {
        ToolbarItem {
            if session.captured {
                Text("Keyboard is in \(MachineFormat.systemName(machine.kind)) · \(ScreenView.releaseSymbols) gives it back")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .foregroundStyle(.white)
                    .background(.tint, in: Capsule())
            }
        }
        ToolbarItem {
            Menu("Send Keys") {
                ForEach(SendKeys.menu(forKind: machine.kind)) { combination in
                    Button {
                        combination.send(to: session.input)
                    } label: {
                        Text("\(combination.title)  \(combination.symbols)")
                    }
                }
            }
            .disabled(session.input == nil)
            .help("Send a key combination that the Mac would keep for itself")
        }
        ToolbarItem {
            Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .help("Enter or leave full screen (⌃⌘F)")
        }
        ToolbarItem {
            Button("Shut Down", systemImage: "power") { library.shutDown(machine) }
                .disabled(library.status(of: machine).state != "running")
                .help("Ask the guest to power off")
        }
    }
}

/// Only numbers the app has: frames a second shown and skipped, and the picture's size.
private struct ScreenStatisticsOverlay: View {
    let session: ScreenSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(session.shownPerSecond) frames a second")
            if session.skippedPerSecond > 0 {
                Text("\(session.skippedPerSecond) skipped a second")
            }
            if let size = session.pictureSize {
                Text("\(String(size.width)) × \(String(size.height))")
            } else {
                Text("No picture")
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
