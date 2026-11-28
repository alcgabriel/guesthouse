// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

/// A row that shows the file chosen and a button to choose one.
struct FileChooserRow: View {
    let title: LocalizedStringKey
    /// What the panel says, as the sentence that asks for the file.
    let message: String
    @Binding var path: String
    /// An optional file can be cleared again.
    var optional = false
    /// What to say beside the file's name, such as its size.
    var detail: String? = nil

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? String(localized: "None chosen") : URL(filePath: path).lastPathComponent)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .truncationMode(.middle)
                    .help(path)
                if let detail, !path.isEmpty {
                    Text(detail).foregroundStyle(.secondary)
                }
                Button("Choose…", action: choose)
                if optional && !path.isEmpty {
                    Button("Clear") { path = "" }
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = message
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path(percentEncoded: false)
        }
    }
}
