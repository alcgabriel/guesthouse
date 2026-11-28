// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

/// Writes what the app's own windows show to image files, for a run with no one at the screen
/// (the screen may be locked, and then nothing else can capture a window): `--snapshot PREFIX`
/// with `--snapshot-at 5,12` writes `PREFIX-5s-1.png` for the first window at five seconds, and
/// so on. `--appearance light|dark` sets how it is drawn, `--open-install windows|ubuntu` opens
/// that confirmation sheet. Each window's own view is drawn, so a sheet is a file of its own.
enum Snapshots {
    private static let arguments = CommandLine.arguments

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static let prefix: String? = value(after: "--snapshot")
    static let times: [Double] = (value(after: "--snapshot-at") ?? "5").split(separator: ",").compactMap { Double($0) }
    static let appearance: String? = value(after: "--appearance")
    static let openInstall: String? = value(after: "--open-install")
    /// `--open-settings general|updates|about` and `--open-menu` host those views in windows of
    /// their own (a run with no one at the screen makes no scene windows, so none would open). `--show-problem gpu|memory|start`: puts up
    /// that message with example words, to see it.
    static let openSettings: String? = value(after: "--open-settings")
    /// `--open-menu`: the menu bar item's window, hosted as a window of its own.
    static let openMenu = arguments.contains("--open-menu")
    /// `--describe-views`: prints, for each window, its visual effect views (material, state)
    /// and its tables, to check the sidebar uses the system's sidebar material.
    /// `--open-report` puts up the bug report sheet for the first machine; with `--report-review`
    /// it goes straight to making the report and showing what is in it (nothing is sent).
    static let openReport = arguments.contains("--open-report")
    static let reportReview = arguments.contains("--report-review")
    static let describeViews = arguments.contains("--describe-views")
    static let showProblem: String? = value(after: "--show-problem")

    /// Called once at launch.
    @MainActor static func start(library: Library) {
        if let appearance {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        if let openInstall, let guest = InstallGuest(rawValue: openInstall) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { library.installing = guest }
        }
        if openSettings != nil || openMenu {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { hostExtras(library: library) }
        }
        if let showProblem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                switch showProblem {
                case "gpu": library.attention = .noGPU(has: "an Intel processor")
                case "memory":
                    library.attention = Problem.from(core: Core.startCheck([
                        "check": "memory", "machine": "Ubuntu", "wanted_mb": 4096, "host_mb": 16384,
                        "running": [["name": "Windows 11", "memory_mb": 12288]],
                    ]))
                case "disk": library.attention = Problem.from(core: Core.startCheck([
                    "check": "disk", "machine": "Windows 11", "size_bytes": 64_000_000_000,
                    "on_disk_bytes": 0, "free_bytes": 31_000_000_000,
                ]))
                case "driver":
                    library.attention = .driverOld(machine: "Windows 11", machineID: "x", released: "0.2.0", reported: "0.1.0")
                default: library.attention = .didNotStart(machine: "Windows 11", machineID: library.machines.first?.id ?? "x")
                }
            }
        }
        if openReport {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                library.reporting = ReportStart(machineID: library.machines.first?.id, kind: .wontStart)
            }
        }
        if describeViews {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { describe() }
        }
        guard let prefix else { return }
        for time in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                MainActor.assumeIsolated { write(prefix: prefix, time: time) }
            }
        }
    }

    /// Windows kept for as long as the app runs.
    @MainActor private static var extras: [NSWindow] = []

    @MainActor private static func hostExtras(library: Library) {
        let content: AnyView
        var size = CGSize(width: 600, height: 620)
        switch openSettings {
        case "updates": content = AnyView(UpdatesSettings())
        case "about": content = AnyView(AboutSettings())
        case "general": content = AnyView(GeneralSettings())
        default:
            content = AnyView(MenuBarContent())
            size = CGSize(width: 340, height: 360)
        }
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: content.environment(library).guesthouseLook()))
        window.title = "Guesthouse Settings"
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: 40, y: 40))
        window.orderFrontRegardless()
        extras.append(window)
    }

    @MainActor private static func describe() {
        func walk(_ view: NSView, _ depth: Int, _ window: String) {
            if let effect = view as? NSVisualEffectView {
                print("view: \(window) effect material=\(effect.material.rawValue) state=\(effect.state.rawValue) blending=\(effect.blendingMode.rawValue) frame=\(Int(effect.frame.width))x\(Int(effect.frame.height))")
            }
            if let table = view as? NSTableView {
                print("view: \(window) table style=\(table.style.rawValue) highlight=\(table.selectionHighlightStyle.rawValue) selected=\(table.selectedRow) rows=\(table.numberOfRows)")
            }
            if let outline = view as? NSOutlineView { print("view: \(window) outline rows=\(outline.numberOfRows)") }
            view.subviews.forEach { walk($0, depth + 1, window) }
        }
        for window in NSApp.windows where window.isVisible {
            print("view: window \(window.title) key=\(window.isKeyWindow) fullSizeContent=\(window.styleMask.contains(.fullSizeContentView))")
            if let root = window.contentView?.superview { walk(root, 0, window.title) }
        }
    }

    @MainActor private static func write(prefix: String, time: Double) {
        for (index, window) in NSApp.windows.filter(\.isVisible).enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let path = "\(prefix)-\(String(format: "%.1f", time))s-\(index + 1).png"
            try? data.write(to: URL(filePath: path))
            print("guesthouse: wrote \(path)")
        }
    }
}
