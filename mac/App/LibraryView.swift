import AppKit
import SwiftUI

/// The library window: machines in a sidebar, the chosen one on the right.
struct LibraryView: View {
    static let windowID = "library"

    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 248, max: 320)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $library.showingNewMachine) {
            NewMachineSheet()
        }
        .sheet(item: $library.installing) { InstallConfirmSheet(guest: $0) }
        .sheet(item: $library.attention) { ProblemSheet(problem: $0) }
        .sheet(item: $library.reporting) { ReportSheet(start: $0) }
        .onAppear {
            reload()
            if let gpu = Library.gpuProblem() { library.attention = gpu }
            openScreenFromLaunch()
        }
        .alert("Could Not Do That", isPresented: .constant(library.requestProblem != nil)) {
            Button("OK") { library.requestProblem = nil }
        } message: {
            Text(library.requestProblem ?? "")
        }
        // Machines can still be made by hand, so look again whenever the app comes forward.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
    }

    private var sidebar: some View {
        @Bindable var library = library
        return List(selection: $library.selection) {
            Section("Machines") {
                if library.machines.isEmpty {
                    Text("No machines yet. The ones you add are listed here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(library.machines) { machine in
                    MachineRow(machine: machine, status: library.status(of: machine))
                        .tag(machine.id)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Menu {
                Button("Install Windows…") { library.installing = .windows }
                Button("Install Ubuntu…") { library.installing = .ubuntu }
                Divider()
                Button("Use a Disk or Installer…") { library.showingNewMachine = true }
            } label: {
                Label("New Machine", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(12)
            .help("Add a machine")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let problem = library.problem {
            ContentUnavailableView(
                "Cannot Read Machines",
                systemImage: "exclamationmark.triangle",
                description: Text(problem)
            )
        } else if library.machines.isEmpty {
            WelcomeView()
        } else if let machine = library.machines.first(where: { $0.id == library.selection }) {
            MachineView(machine: machine)
                .id(machine.id)
        } else {
            ContentUnavailableView("No Machine Selected", systemImage: "sidebar.left")
        }
    }

    /// `--screen NAME` opens that machine's screen at launch.
    private func openScreenFromLaunch() {
        guard let name = LaunchOptions.screen else { return }
        if let machine = library.machines.first(where: { $0.name == name }), machine.frames != nil {
            openWindow(id: ScreenWindow.windowID, value: machine.id)
        } else {
            print("guesthouse: no machine called \(name) with a screen")
        }
    }

    private func reload() {
        library.reload()
        if library.selection == nil || !library.machines.contains(where: { $0.id == library.selection }) {
            library.selection = library.machines.first?.id
        }
    }
}

extension MachineStatus {
    /// Green running, amber on its way, red failed, grey stopped.
    var color: Color {
        switch state {
        case "running": .green
        case "starting", "shutting_down": .orange
        case "failed": .red
        default: .gray
        }
    }
}
