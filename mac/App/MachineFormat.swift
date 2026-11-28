import Foundation

/// Words and numbers for the machine pane, kept apart from the views so they can be tried
/// without a window.
nonisolated enum MachineFormat {
    /// What a machine of this `kind` is, in a person's words.
    static func kindDescription(_ kind: String) -> String {
        kind == "windows" ? String(localized: "Windows 11 on ARM") : kind
    }

    /// A display mode such as `1024x768@60` as "1024 × 768, 60 Hz". Anything that does not
    /// read that way is shown as it is.
    static func mode(_ text: String) -> String {
        let halves = text.split(separator: "@", maxSplits: 1)
        let sizes = halves.first?.split(separator: "x", maxSplits: 1)
        guard halves.count == 2, let sizes, sizes.count == 2,
              let width = Int(sizes[0]), let height = Int(sizes[1]), let rate = Int(halves[1])
        else { return text }
        // Plain digits: a size is not a quantity, so no "1,024".
        return String(localized: "\(String(width)) × \(String(height)), \(String(rate)) Hz")
    }

    /// Where a machine's graphics device is, in plain words.
    static func graphicsTitle(_ graphics: String) -> String {
        graphics == "qemu"
            ? String(localized: "QEMU's own device")
            : String(localized: "Protected graphics (recommended)")
    }

    /// A display mode's size and its rate apart, "1024 × 768" and "60 Hz", for a card that says
    /// them on two lines; nil when the text is not a mode.
    static func modeParts(_ text: String) -> (size: String, rate: String)? {
        let whole = mode(text)
        guard whole != text, let comma = whole.range(of: ", ") else { return nil }
        return (String(whole[..<comma.lowerBound]), String(whole[comma.upperBound...]))
    }

    /// The system's name on its own, for sentences such as "the keyboard is in Windows".
    static func systemName(_ kind: String) -> String {
        kind == "windows" ? "Windows" : kind
    }

    /// Memory in megabytes as "6 GB".
    static func memory(megabytes: Int) -> String {
        Measurement(value: Double(megabytes), unit: UnitInformationStorage.mebibytes)
            .formatted(.byteCount(style: .memory))
    }

    /// A size in bytes as Finder writes it.
    static func fileSize(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// The disk in a sentence: how big Windows sees it, and how much of that the Mac has
    /// actually given up. A disk image grows as it is used, so the two differ.
    static func disk(size: Int64?, onDisk: Int64?) -> String {
        switch (size, onDisk) {
        case let (size?, onDisk?):
            String(localized: "\(fileSize(size)), \(fileSize(onDisk)) used on this Mac")
        case let (size?, nil):
            fileSize(size)
        default:
            String(localized: "The disk image is not there")
        }
    }
}
