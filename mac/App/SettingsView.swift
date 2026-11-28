import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Updates", systemImage: "arrow.triangle.2.circlepath") { UpdatesSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 600, height: 620)
    }
}

/// The brand's blue, the accent the design uses unless the person asks for the system's.
enum Brand {
    static let blue = Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xDF / 255)
}

extension View {
    /// The accent and colours the person chose in Settings, for the root of each window.
    func guesthouseLook() -> some View {
        modifier(LookModifier())
    }
}

private struct LookModifier: ViewModifier {
    @AppStorage(SettingsKey.colours) private var colours = "system"
    @AppStorage(SettingsKey.accent) private var accent = "blue"

    func body(content: Content) -> some View {
        content
            .tint(accent == "blue" ? Brand.blue : nil)
            .preferredColorScheme(colours == "dark" ? .dark : colours == "light" ? .light : nil)
    }
}

/// What the app does around its windows, how it looks, the screen windows, and (for those who
/// need it) where things are kept.
struct GeneralSettings: View {
    @Environment(Library.self) private var library
    @AppStorage(SettingsKey.qemuPath) private var qemuPath = ""
    @AppStorage(SettingsKey.quitBehavior) private var quitBehavior = "ask"
    @AppStorage(SettingsKey.menuBarItem) private var menuBarItem = true
    @AppStorage(SettingsKey.colours) private var colours = "system"
    @AppStorage(SettingsKey.accent) private var accent = "blue"
    @AppStorage(SettingsKey.showScreenStatistics) private var showStatistics = false
    @State private var opensAtLogin = LoginItem.isOn
    @State private var loginProblem: String?
    private let folder = Core.machinesFolder

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Guesthouse when you log in", isOn: Binding(
                    get: { opensAtLogin },
                    set: { on in
                        loginProblem = LoginItem.set(on)
                        opensAtLogin = LoginItem.isOn
                    }))
                if let loginProblem { Text(loginProblem).font(.callout).foregroundStyle(.red) }
                Toggle(isOn: $menuBarItem) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Guesthouse in the menu bar while a machine runs")
                        Text("Machines keep running when the window is closed").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Picker("When quitting with machines running", selection: $quitBehavior) {
                    Text("Ask").tag("ask")
                    Text("Keep Running").tag("keep")
                    Text("Shut Down All").tag("shutdown")
                }
            }
            Section("Look") {
                Picker("Colours", selection: $colours) {
                    Text("Follow macOS").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
                Picker("Accent", selection: $accent) {
                    Text("Guesthouse blue").tag("blue")
                    Text("Follow macOS").tag("system")
                }
                .pickerStyle(.segmented)
            }
            Section("Screen windows") {
                LabeledContent("Give the keyboard back to the Mac with") {
                    Text(ScreenView.releaseSymbols)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                Toggle("Show frames a second", isOn: $showStatistics)
            }
            Section("Where things are") {
                LabeledContent("Machines folder") {
                    VStack(alignment: .trailing) {
                        Text(folder?.path(percentEncoded: false) ?? String(localized: "None"))
                            .textSelection(.enabled)
                            .truncationMode(.middle)
                        Button("Show in Finder", action: showInFinder)
                            .disabled(!folderExists)
                            .help(folderExists ? "" : "The folder is made with the first machine")
                    }
                }
                LabeledContent("QEMU") {
                    HStack {
                        TextField("QEMU", text: $qemuPath, prompt: Text("Found automatically"))
                            .labelsHidden()
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseQEMU)
                    }
                }
                QEMUInUse(title: "In use", location: ToolLocation.find(.qemu, setting: qemuPath))
                QEMUInUse(title: "Protected graphics: QEMU", location: ToolLocation.find(.pvgQemu, setting: qemuPath))
                QEMUInUse(title: "Protected graphics: process", location: ToolLocation.find(.pvgHost))
                LabeledContent("Agent") {
                    Text(library.agent.route)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var folderExists: Bool {
        guard let folder else { return false }
        return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
    }

    private func showInFinder() {
        guard let folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func chooseQEMU() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose the QEMU program that runs the machines")
        if panel.runModal() == .OK, let url = panel.url {
            qemuPath = url.path(percentEncoded: false)
        }
    }
}

/// Which QEMU is in use and why, or what is missing.
private struct QEMUInUse: View {
    let title: LocalizedStringKey
    let location: ToolLocation

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                switch location {
                case .found(let path, _, let why):
                    Text(path)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                    Text(why)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .missing(let sentence):
                    Text(sentence)
                        .foregroundStyle(.red)
                }
            }
            .multilineTextAlignment(.trailing)
        }
    }
}
