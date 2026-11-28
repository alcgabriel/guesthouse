import Foundation

/// What to tell the person about a machine's screen on this Mac.
nonisolated enum ScreenStatus {
    /// The picture as the open window knows it.
    enum Picture: Equatable {
        case waiting
        case showing(width: Int, height: Int, framesPerSecond: Int)
    }

    /// One line on the screen. `picture` is nil when no screen window is open.
    static func line(hasScreen: Bool, startable: Bool, machineAlive: Bool, picture: Picture?) -> String {
        guard hasScreen else { return String(localized: "This machine has no screen to show.") }
        // A machine the app runs has no picture while it is off; one run by hand may.
        if startable && !machineAlive && picture == nil {
            return String(localized: "There is no screen while the machine is turned off.")
        }
        switch picture {
        case nil:
            return String(localized: "The screen window is closed. Open Screen to see the machine.")
        case .waiting:
            return String(localized: "Waiting for the first picture from the machine.")
        case let .showing(width, height, rate):
            return String(localized: "Showing \(String(width)) × \(String(height)), \(rate) frames a second.")
        }
    }

    /// The frames the machine sends a second, said so that a still picture does not look like a
    /// fault: a desktop nobody touches sends none.
    static func rateText(framesPerSecond: Int) -> String {
        framesPerSecond > 0
            ? String(localized: "\(framesPerSecond) frames a second")
            : String(localized: "The picture is still")
    }

    /// How to give the keyboard back and use full screen, as the screen window works.
    static var keysHelp: String {
        String(localized: "Click the picture to type into the machine. Press Control and Option together (⌃⌥) to give the keyboard back to the Mac. Control-Command-F (⌃⌘F) enters and leaves full screen.")
    }
}
