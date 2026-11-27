// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// The firmware files that sit beside a disk image, found by their names: a machine's folder
/// from the lab has `code.fd`, `vars.fd` and often `pvgfb.rom` next to its `win.img`.
nonisolated struct FirmwareFiles: Equatable {
    var code: String?
    var vars: String?
    var optionROM: String?

    /// Whether both firmware files, which a machine needs to start, were found.
    var complete: Bool { code != nil && vars != nil }

    /// Sorts files by what their names say: `.rom` is the option ROM, a name with "code" the
    /// firmware code, one with "vars" its variables. Anything else is left out.
    static func sorted(_ paths: [String]) -> FirmwareFiles {
        var found = FirmwareFiles()
        for path in paths.sorted() {
            let name = URL(filePath: path).lastPathComponent.lowercased()
            if name.hasSuffix(".rom") {
                found.optionROM = found.optionROM ?? path
            } else if name.hasSuffix(".fd") || name.hasSuffix(".bin") {
                if name.contains("code") { found.code = found.code ?? path }
                if name.contains("vars") { found.vars = found.vars ?? path }
            }
        }
        return found
    }

    /// The files in the folder of `disk`.
    static func beside(disk: String) -> FirmwareFiles {
        guard !disk.isEmpty else { return FirmwareFiles() }
        let folder = URL(filePath: disk).deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return sorted(names.map { folder.appending(path: $0).path(percentEncoded: false) })
    }
}
