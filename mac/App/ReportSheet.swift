// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

/// Where a report starts from: which machine and what kind of problem, when the place it was asked
/// for already knows.
struct ReportStart: Identifiable {
    let id = UUID()
    var machineID: String?
    var kind: ReportKind = .other
}

/// Sending a bug report, as the Linux app does it: say what went wrong, look at exactly what goes
/// in, and press Send. Nothing leaves this Mac before that. If it cannot be sent it can be saved
/// to a file to attach.
struct ReportSheet: View {
    let start: ReportStart
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var machineID: String?
    @State private var kind: ReportKind = .other
    @State private var includeSerial = true
    @State private var description = ""
    @State private var contact = ""
    @State private var phase = Phase.editing
    @State private var chosenFile: String?

    private enum Phase {
        case editing
        case gathering
        case reviewing(PreparedReport)
        case sending(PreparedReport)
        case sent(id: String, link: String)
        case notSent(reason: String, report: PreparedReport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send a Report").font(.title2.weight(.semibold))
            switch phase {
            case .editing: form
            case .gathering: progress(String(localized: "Gathering what goes in…"))
            case .reviewing(let report): review(report)
            case .sending: progress(String(localized: "Sending…"))
            case .sent(let id, let link): sent(id: id, link: link)
            case .notSent(let reason, let report): notSent(reason: reason, report: report)
            }
        }
        .padding(24)
        .frame(width: 720)
        .onAppear {
            machineID = start.machineID
            kind = start.kind
            if Snapshots.reportReview {
                description = "It went black after the first start."
                gather()
            }
        }
    }

    // MARK: Editing

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ReportWords.whatIsSent).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Machine", selection: $machineID) {
                    Text(ReportWords.noMachine).tag(String?.none)
                    ForEach(library.machines) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Kind of Problem", selection: $kind) {
                    ForEach(ReportKind.allCases) { Text($0.label).tag($0) }
                }
                if machineID != nil {
                    Toggle(isOn: $includeSerial) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Guest's Serial Log")
                            Text(ReportWords.serialNote).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("What Went Wrong")
                    Text("What you did, what you expected, and what happened instead")
                        .font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $description)
                        .frame(height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                        .accessibilityLabel("What went wrong")
                }
                TextField("How to Reach You (Optional)", text: $contact)
            }
            .formStyle(.columns)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Review What Goes In", action: gather)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: Reviewing

    private func review(_ report: PreparedReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What It Holds").font(.headline)
            Text("This is exactly what is sent. Read any file before you press Send.")
                .foregroundStyle(.secondary)
            if let warning = report.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                List(report.files, selection: $chosenFile) { file in
                    HStack {
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Self.size(file.bytes)).foregroundStyle(.secondary).font(.caption)
                    }
                    .tag(file.name)
                }
                .frame(width: 260, height: 260)
                ScrollView {
                    Text(preview(of: report))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            }
            if !report.missing.isEmpty {
                DisclosureGroup("Not in it") {
                    ForEach(report.missing) { Text("\($0.name): \($0.reason)").font(.callout).foregroundStyle(.secondary) }
                }
            }
            HStack {
                Text("\(Self.size(report.bytes)) packed").foregroundStyle(.secondary)
                Spacer()
                Button("Back") { phase = .editing }
                Button("Save to File…") { save(report) }
                Button("Send") { send(report) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The text of the chosen file, as it is in the report.
    private func preview(of report: PreparedReport) -> String {
        let name = chosenFile ?? report.files.first?.name ?? ""
        let url = URL(filePath: report.folder).appending(path: name)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? String(localized: "This file cannot be shown.")
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: After

    private func sent(id: String, link: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report Sent").font(.headline)
            Text(ReportWords.sentBody).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(id).font(.title3.monospaced()).textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(id, forType: .string)
                }
            }
            HStack {
                Spacer()
                Button("No") { dismiss() }
                Button("Open an Issue") {
                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func notSent(reason: String, report: PreparedReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The Report Wasn't Sent").font(.headline)
            Text(ReportWords.notSentBody(reason: reason)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                Button("Save to File…") { save(report) }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func gather() {
        phase = .gathering
        var request: [String: Any] = [
            "kind": kind.rawValue, "description": description, "contact": contact,
            "include_serial": includeSerial, "app_version": AppInfo.version,
        ]
        if let machineID, let machine = library.machines.first(where: { $0.id == machineID }) {
            request["machine"] = machine.agentID
            request["machine_running"] = library.status(of: machine).isAlive
        }
        let json = (try? JSONSerialization.data(withJSONObject: request)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        Task {
            let result = await Task.detached { Core.prepareReport(json: json) }.value
            switch result {
            case .success(let report):
                chosenFile = report.files.first(where: { $0.bytes > 0 })?.name ?? report.files.first?.name
                phase = .reviewing(report)
            case .failure(let failure):
                phase = .notSent(reason: failure.text, report: PreparedReport(
                    archive: "", folder: "", files: [], missing: [], notes: [], summary: [:], summaryHeader: "", bytes: 0, warning: nil))
            }
        }
    }

    /// The one place a report leaves this Mac, reached only from the Send button.
    private func send(_ report: PreparedReport) {
        phase = .sending(report)
        Task {
            let result = await Task.detached { Core.sendReport(report) }.value
            switch result {
            case .success(let sent): phase = .sent(id: sent.id, link: sent.issueLink)
            case .failure(let failure): phase = .notSent(reason: failure.text, report: report)
            }
        }
    }

    private func save(_ report: PreparedReport) {
        guard !report.archive.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(filePath: report.archive).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.copyItem(atPath: report.archive, toPath: url.path)
        } catch {
            library.requestProblem = String(localized: "The report couldn't be saved there: \(error.localizedDescription)")
        }
    }
}
