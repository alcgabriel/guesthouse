// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// A combination of keys to send the guest as one: the ones the Mac would keep for itself
/// (⌃⌥⌫ is not a Mac shortcut, but ⌘Tab and the like never reach the window), pressed and
/// released through the same input as everything else.
struct SendKeys: Identifiable {
    let title: String
    /// The keys as the menu shows them on the right: "Ctrl Alt Del".
    let symbols: String
    /// Modifier keys, then the key, by macOS key code.
    let modifiers: [UInt16]
    let key: UInt16
    /// Only a Linux machine has a text console to switch to.
    var linuxOnly = false

    var id: String { title }

    // macOS key codes (core/src/keys.rs maps them to QEMU's key names).
    private static let control: UInt16 = 0x3B
    private static let option: UInt16 = 0x3A
    private static let command: UInt16 = 0x37
    private static let forwardDelete: UInt16 = 0x75
    private static let tab: UInt16 = 0x30
    private static let f4: UInt16 = 0x76
    private static let f3: UInt16 = 0x63
    private static let f2: UInt16 = 0x78
    private static let l: UInt16 = 0x25
    /// Print Screen: a code of the core's own, since a Mac keyboard has no such key.
    private static let printScreen: UInt16 = 0xF001

    /// The menu, in the order of the design: for any machine, then those for Linux.
    static let all = [
        SendKeys(title: String(localized: "Control-Alt-Delete"), symbols: "Ctrl Alt Del", modifiers: [control, option], key: forwardDelete),
        SendKeys(title: String(localized: "Windows key"), symbols: "Win", modifiers: [], key: command),
        SendKeys(title: String(localized: "Windows key and L, lock"), symbols: "Win L", modifiers: [command], key: l),
        SendKeys(title: String(localized: "Print Screen"), symbols: "PrtSc", modifiers: [], key: printScreen),
        SendKeys(title: String(localized: "Alt-Tab"), symbols: "Alt Tab", modifiers: [option], key: tab),
        SendKeys(title: String(localized: "Alt-F4"), symbols: "Alt F4", modifiers: [option], key: f4),
        SendKeys(title: String(localized: "Switch to a text console"), symbols: "Ctrl Alt F3", modifiers: [control, option], key: f3, linuxOnly: true),
        SendKeys(title: String(localized: "Back to the desktop"), symbols: "Ctrl Alt F2", modifiers: [control, option], key: f2, linuxOnly: true),
    ]

    /// The menu for a machine of this kind.
    static func menu(forKind kind: String) -> [SendKeys] {
        all.filter { !$0.linuxOnly || kind != "windows" }
    }

    /// Presses the modifiers, taps the key, lets the modifiers go.
    func send(to input: GuestInput?) {
        guard let input else { return }
        for modifier in modifiers { input.modifier(modifier, flagOn: true) }
        input.key(key, down: true)
        input.key(key, down: false)
        for modifier in modifiers.reversed() { input.modifier(modifier, flagOn: false) }
    }
}
