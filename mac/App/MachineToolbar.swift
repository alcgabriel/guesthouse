import AppKit
import SwiftUI

/// Which of the pane's dialogs is up.
struct MachineDialogs {
    var renaming = false
    var newName = ""
    var removing = false
}

/// The toolbar: Start or Shut Down, a More menu, and Open Screen as the main action.
struct MachineToolbar: ToolbarContent {
    let machine: Machine
    @Binding var dialogs: MachineDialogs
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.qemuPath) private var qemuSetting = ""

    private var status: MachineStatus { library.status(of: machine) }
    /// Why Start is off for want of a program, if it is. Reads the Settings path so it looks
    /// again when one is chosen.
    private var startProblem: String? { _ = qemuSetting; return library.startPlan(for: machine).problem }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if status.isAlive {
                Button("Shut Down", systemImage: "power") { library.shutDown(machine) }
                    .labelStyle(.titleAndIcon)
                    .disabled(status.state != "running")
                    .help("Ask the guest to power off")
            } else {
                Button("Start", systemImage: "play.fill") { library.start(machine) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
                    .help(startHelp)
            }
            Menu {
                Button("Force Off") { library.forceOff(machine) }
                    .disabled(!status.canForceOff)
                Divider()
                Button("Rename…") {
                    dialogs.newName = machine.name
                    dialogs.renaming = true
                }
                Button("Remove…", role: .destructive) { dialogs.removing = true }
                    .disabled(!library.canRemove(machine))
                Divider()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: machine.folder)])
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .help("More actions")
            // Prominent while the machine is up; when it is off, Start is the main action.
            Button("Open Screen", systemImage: "display") {
                openWindow(id: ScreenWindow.windowID, value: machine.id)
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .tint(status.isAlive ? .accentColor : .gray)
            .disabled(!canOpenScreen)
            .help(machine.frames == nil ? "This machine has no screen to show" : "Show the machine's screen in a window")
        }
    }

    private var canStart: Bool {
        Rules.canStart(
            startable: machine.startable, problem: startProblem != nil,
            agentConnected: library.agent.connected, state: status.state)
    }

    private var startHelp: String {
        if !machine.startable { return "machine.json has no firmware files, so the app cannot start this machine" }
        if let startProblem { return startProblem }
        if !library.agent.connected { return "The agent is not running" }
        return "Start the machine"
    }

    /// A machine the app runs shows its screen while it is up; one run by hand shows its
    /// screen whenever it has one.
    private var canOpenScreen: Bool {
        Rules.canOpenScreen(hasScreen: machine.frames != nil, startable: machine.startable, state: status.state)
    }
}

extension View {
    /// The Rename and Remove dialogs the toolbar's More menu opens.
    func machineDialogs(machine: Machine, dialogs: Binding<MachineDialogs>) -> some View {
        modifier(MachineDialogsModifier(machine: machine, dialogs: dialogs))
    }
}

private struct MachineDialogsModifier: ViewModifier {
    let machine: Machine
    @Binding var dialogs: MachineDialogs
    @Environment(Library.self) private var library

    func body(content: Content) -> some View {
        content
            .alert("Rename Machine", isPresented: $dialogs.renaming) {
                TextField("Name", text: $dialogs.newName)
                Button("Rename") { library.rename(machine, to: dialogs.newName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a new name for \(machine.name).")
            }
            .confirmationDialog("Remove \(machine.name)?", isPresented: $dialogs.removing, titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) { library.remove(machine) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(machine.name) and its disk go to the Trash. You can put them back from there until the Trash is emptied.")
            }
    }
}
