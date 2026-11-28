import AppKit
import SwiftUI

/// About the machine: its name, system and how to sign in, then what to do if something is wrong,
/// then removing it, with the paths and internal names under a disclosure for those who look.
struct DetailsTab: View {
    let machine: Machine
    @Binding var dialogs: MachineDialogs
    @Environment(Library.self) private var library
    @State private var showingTechnical = false
    @State private var usage: DiskUsage?
    private var graphics: GraphicsCounts? { library.graphics[machine.agentID] }

    var body: some View {
        VStack(spacing: 16) {
            Form {
                about
                trouble
                Section {
                    LabeledContent {
                        Button("Delete…", role: .destructive) { dialogs.removing = true }
                            .disabled(!library.canRemove(machine))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete this machine")
                            Text("Its disk and everything on it go to the Trash.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    DisclosureGroup("Technical details", isExpanded: $showingTechnical) { technical }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .task(id: machine.disk) { usage = DiskUsage.read(path: machine.disk) }
    }

    private var about: some View {
        Section("About this machine") {
            LabeledContent("Name") {
                HStack {
                    Text(machine.name)
                    Button("Rename") {
                        dialogs.newName = machine.name
                        dialogs.renaming = true
                    }
                }
            }
            LabeledContent("System", value: MachineFormat.kindDescription(machine.kind))
            if let install = library.install(of: machine), !install.account.isEmpty {
                GuestSignIn(machine: machine, account: install.account)
            }
            LabeledContent("Files") {
                HStack {
                    Text(usage.map { String(localized: "\(MachineFormat.fileSize($0.onDisk)) in Guesthouse's folder on this Mac") } ?? "—")
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: machine.folder)])
                    }
                }
            }
        }
    }

    private var trouble: some View {
        Section("If something is wrong") {
            LabeledContent {
                Button("Send Report") { library.report(machine: machine, kind: .other) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send a report")
                    Text("This machine's log and this Mac's model. You see it before it goes.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            LabeledContent {
                Button("Reinstall Driver") {}
                    .disabled(true)
                    .help("Needs the guest's help, which is not built yet")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install the graphics driver again")
                    Text("Puts the current driver back. Nothing else in the machine is touched.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Show the log") {
                Button("Show Log") { showLog() }
            }
        }
    }

    @ViewBuilder
    private var technical: some View {
        row("Folder", machine.folder)
        row("Identifier", machine.agentID)
        row("Disk image", machine.disk)
        row("Graphics", MachineFormat.graphicsTitle(machine.graphics))
        ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in row(tool.title, tool.value) }
        if let frames = machine.frames { row("Screen name", frames) }
        if let qmp = machine.qmp { row("Input socket", qmp) }
        if machine.graphics == "guarded", let counts = graphics {
            row("Frames published", counts.published.formatted())
            row("Refused by the guard", counts.refused.formatted())
        }
    }

    // MARK: Actions

    private func showLog() {
        let folder = URL(filePath: machine.folder)
        let log = ["serial.log", "qemu.log"].map { folder.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting([log ?? folder])
    }

    /// The programs this machine's start would run, as found now.
    private var tools: [(title: LocalizedStringKey, value: String)] {
        let setting = Library.qemuSetting
        func line(_ location: ToolLocation) -> String {
            switch location {
            case .found(let path, _, _): path
            case .missing(let sentence): sentence
            }
        }
        if machine.graphics == "qemu" {
            return [("QEMU", line(ToolLocation.find(.qemu, setting: setting)))]
        }
        return [
            ("QEMU with protected graphics", line(ToolLocation.find(.pvgQemu, setting: setting))),
            ("Graphics process", line(ToolLocation.find(.pvgHost))),
        ]
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).textSelection(.enabled).truncationMode(.middle)
        }
    }
}
