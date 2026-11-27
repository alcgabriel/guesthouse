import SwiftUI

/// This Mac's size, for saying how much of it a machine has.
enum ThisMac {
    static var processors: Int { ProcessInfo.processInfo.activeProcessorCount }
    static var memoryMB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_048_576) }

    /// Memory that is free now or that the Mac can give back at once (inactive, purgeable and
    /// speculative pages), in megabytes; nil if the system will not say.
    static var availableMB: Int? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count)
            + UInt64(stats.speculative_count)
        return Int(pages * UInt64(getpagesize()) / 1_048_576)
    }
}

/// What the machine has, in four groups: its size, its screen, its graphics and how it starts.
/// Processors and memory change while it is turned off and take effect at its next start; the
/// screen's two choices are the app's and take effect at once.
struct HardwareTab: View {
    let machine: Machine
    @Environment(Library.self) private var library
    @State private var cores = 0
    @State private var memoryGB = 0
    @State private var problems: [String] = []
    @State private var usage: DiskUsage?
    @AppStorage private var follows: Bool
    @AppStorage private var sharp: Bool

    init(machine: Machine) {
        self.machine = machine
        _follows = AppStorage(wrappedValue: true, ScreenPrefs.followsKey(machine.id))
        _sharp = AppStorage(wrappedValue: true, ScreenPrefs.sharpKey(machine.id))
    }

    private var running: Bool { library.status(of: machine).isAlive }
    private var hostGB: Int { ThisMac.memoryMB / 1024 }

    /// The processor counts to choose from, always including the machine's own.
    private var choices: [Int] {
        var all = [2, 4, 6, 8, 12, 16].filter { $0 <= ThisMac.processors }
        if !all.contains(machine.cores) { all.append(machine.cores) }
        return all.sorted()
    }

    private var memoryRange: ClosedRange<Int> {
        2...max(2, hostGB - 2, machine.memoryMB / 1024)
    }

    private var changed: Bool {
        cores != machine.cores || memoryGB * 1024 != machine.memoryMB
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                sizeSection
                screenSection
                graphicsSection
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
            HStack {
                Text(running
                    ? "Shut the machine down to change its processors or memory."
                    : "Processors and memory change at its next start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Revert") { load() }
                    .disabled(!changed)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!changed || running)
            }
        }
        .onAppear(perform: load)
        .onChange(of: machine) { load() }
        .task(id: machine.disk) { usage = DiskUsage.read(path: machine.disk) }
    }

    // MARK: Groups

    private var sizeSection: some View {
        Section("Size") {
            LabeledContent("Processors") {
                HStack {
                    Picker("Processors", selection: $cores) {
                        ForEach(choices, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Text("of this Mac's \(ThisMac.processors)").foregroundStyle(.secondary)
                }
            }
            .disabled(running)
            LabeledContent("Memory") {
                HStack {
                    Slider(value: Binding(get: { Double(memoryGB) }, set: { memoryGB = Int($0) }),
                           in: Double(memoryRange.lowerBound)...Double(memoryRange.upperBound), step: 1)
                        .accessibilityLabel("Memory")
                    Text("\(memoryGB) GB").fontWeight(.semibold)
                    Text("of \(hostGB) GB").foregroundStyle(.secondary)
                }
            }
            .disabled(running)
            LabeledContent("Disk") {
                Text(MachineFormat.disk(size: usage?.size, onDisk: usage?.onDisk)).foregroundStyle(.secondary)
            }
        }
    }

    /// A Linux machine on the protected path takes its window's size; Windows cannot be told yet.
    private var followsNote: String {
        if machine.kind == "linux" && machine.graphics == "guarded" {
            return String(localized: "The machine's screen is always the size of its window. Sharp or Standard counts from the next start.")
        }
        return String(localized: "The machine's screen is always the size of its window. Not working yet: the guest cannot be told the size, so it keeps its own.")
    }

    private var screenSection: some View {
        Section("Screen") {
            Toggle(isOn: $follows) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Size follows the window")
                    Text(followsNote).font(.callout).foregroundStyle(.secondary)
                }
            }
            LabeledContent {
                Picker("On a Retina display", selection: $sharp) {
                    Text("Sharp").tag(true)
                    Text("Standard").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .disabled(!follows)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On a Retina display")
                    Text("Sharp draws every pixel. Standard is lighter on the GPU.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var graphicsSection: some View {
        Section("Graphics") {
            Picker("Drawn by", selection: Binding(
                get: { machine.graphics },
                set: { choice in
                    if let problem = Core.setGraphics(machine: machine.agentID, to: choice) { problems = [problem] }
                    library.reload()
                }
            )) {
                Text("This Mac's GPU, protected").tag("guarded")
                Text("QEMU's own device").tag("qemu")
            }
            .disabled(running)
            LabeledContent("Guesthouse graphics driver") {
                Text(driverText).foregroundStyle(.secondary)
            }
            if machine.graphics == "qemu" {
                Text("QEMU's own device runs inside QEMU, without the guard that protects this Mac. Use it to compare, not for everyday work.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// What is known of the driver in the guest: whether the install put it in. A version and an
    /// update check need the guest to report one, which it does not yet.
    private var driverText: String {
        guard let install = library.install(of: machine) else { return String(localized: "Not reported by this machine") }
        let installed = install.steps.first { $0.name == "install_driver" }?.status == "done"
        return installed ? String(localized: "Installed by Guesthouse") : String(localized: "Not installed")
    }

    // MARK: Actions

    private func load() {
        cores = machine.cores
        memoryGB = machine.memoryMB / 1024
        problems = []
    }

    private func save() {
        problems = Core.setHardware(machine: machine.agentID, cores: cores, memoryMB: memoryGB * 1024)
        library.reload()
    }
}
