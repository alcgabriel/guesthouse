import AppKit
import SwiftUI

/// The tabs of a machine's pane.
enum MachineTab: String, CaseIterable, Identifiable {
    case overview, sharing, hardware, details

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .sharing: "Sharing"
        case .hardware: "Hardware"
        case .details: "Details"
        }
    }
}

/// A machine's pane: the toolbar that runs it, tabs, and the tab chosen.
struct MachineView: View {
    let machine: Machine
    @State private var tab = LaunchOptions.tab.flatMap(MachineTab.init(rawValue:)) ?? MachineTab.overview
    @State private var dialogs = MachineDialogs()
    @Environment(Library.self) private var library

    var body: some View {
        if library.showsInstall(machine), let install = library.install(of: machine) {
            InstallView(machine: machine, install: install)
                .navigationTitle(machine.name)
                .toolbar { MachineToolbar(machine: machine, dialogs: $dialogs) }
                .machineDialogs(machine: machine, dialogs: $dialogs)
        } else {
            tabs
        }
    }

    /// The sections are a segmented control in the toolbar, as in Mac apps with a few pages.
    private var tabs: some View {
        ScrollView {
            content
                .padding(20)
        }
        .navigationTitle(machine.name)
        .navigationSubtitle(MachineFormat.kindDescription(machine.kind))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $tab) {
                    ForEach(MachineTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            MachineToolbar(machine: machine, dialogs: $dialogs)
        }
        .machineDialogs(machine: machine, dialogs: $dialogs)
        .onChange(of: library.tabRequest) { _, request in
            if let request {
                tab = request
                library.tabRequest = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: OverviewTab(machine: machine)
        case .sharing: SharingTab(machine: machine)
        case .hardware: HardwareTab(machine: machine)
        case .details: DetailsTab(machine: machine, dialogs: $dialogs)
        }
    }
}
