// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

/// Quitting: machines belong to the agent, so by default they carry on. With some running, the
/// app asks once what to do, and can remember the answer (Settings, General, changes it).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let library = Library.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The programs are asked what they can do once, off the main thread, so the first window
        // does not wait for it.
        let setting = Library.qemuSetting
        Task.detached {
            for tool in [Tool.pvgQemu, .pvgHost] { _ = ToolLocation.find(tool, setting: setting) }
        }
        library.reload()
        library.agent.maintain()
        library.runLaunchActions()
        Snapshots.start(library: library)
        UpdateCheck.runIfDue()
        // A run from the command line, with no one at the screen, has been seen to start with
        // no SwiftUI window at all. If there is none shortly after launch, make them here.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.windowGrace) { [weak self] in
            MainActor.assumeIsolated { self?.presentWindowsIfNone() }
        }
        if LaunchOptions.printStates {
            // For a run with no one at the screen: which windows this process has.
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let titles = NSApp.windows.map { "\($0.title) \(Int($0.frame.width))x\(Int($0.frame.height)) visible \($0.isVisible)" }
                    print("windows: \(titles.isEmpty ? "none" : titles.joined(separator: ", "))")
                }
            }
        }
        if let seconds = LaunchOptions.quitAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
        }
    }

    /// How long the scene set-up gets to make the first window before the app makes it.
    private static let windowGrace: TimeInterval = 2

    /// Windows made by hand, kept for as long as the app runs.
    private var fallbackWindows: [NSWindow] = []

    /// The library window, hosted directly, for when the scenes made none.
    private func presentWindowsIfNone() {
        // The menu bar item is a window too, but not one a person works in.
        guard !NSApp.windows.contains(where: { $0.styleMask.contains(.titled) }) else { return }
        library.reload()
        // Its own appearing opens the screen window of `--screen NAME`, as it would in a scene.
        let made = [Self.hostWindow(title: "Guesthouse", size: CGSize(width: 1100, height: 720),
                                    content: LibraryView().environment(library).guesthouseLook())]
        fallbackWindows = made
        made.forEach { $0.makeKeyAndOrderFront(nil) }
        print("guesthouse: the scenes made no window, so the library was made directly")
    }

    private static func hostWindow<Content: View>(title: String, size: CGSize, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard library.agent.anyAlive else { return .terminateNow }
        if library.quitShutsDown { return shutDownAll(library) }
        switch UserDefaults.standard.string(forKey: SettingsKey.quitBehavior) ?? "ask" {
        case "keep":
            return .terminateNow
        case "shutdown":
            return shutDownAll(library)
        default:
            return ask(library)
        }
    }

    private func ask(_ library: Library) -> NSApplication.TerminateReply {
        let count = library.agent.aliveMachineIDs.count
        let alert = NSAlert()
        alert.messageText = count == 1
            ? String(localized: "A machine is still running.")
            : String(localized: "\(count) machines are still running.")
        alert.informativeText = String(localized: "They can keep running without the app, and the app will find them again when it opens.")
        alert.addButton(withTitle: String(localized: "Keep Running"))
        alert.addButton(withTitle: String(localized: "Shut Down All"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        let response = alert.runModal()
        let remember = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn:
            if remember { UserDefaults.standard.set("keep", forKey: SettingsKey.quitBehavior) }
            return .terminateNow
        case .alertSecondButtonReturn:
            if remember { UserDefaults.standard.set("shutdown", forKey: SettingsKey.quitBehavior) }
            return shutDownAll(library)
        default:
            return .terminateCancel
        }
    }

    /// Asks every running guest to power off. The requests are written out at once, without
    /// waiting for answers: the app is quitting and the agent acts on what it has been sent.
    private func shutDownAll(_ library: Library) -> NSApplication.TerminateReply {
        for machine in library.machines where library.agent.status(of: machine).state == "running" {
            library.agent.sendShutDownWithoutAnswer(machine)
        }
        // A moment for the lines to leave the app.
        Thread.sleep(forTimeInterval: 0.2)
        return .terminateNow
    }
}
