// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation

/// How big a machine's screen should be so that it fills its window exactly. The window's size in
/// points is the machine's screen size in points; what changes is how many pixels it is drawn
/// with. Sharp asks for twice the points each way and 200% scaling, so every pixel of a Retina
/// display is the machine's own; Standard asks for the points as pixels and the Mac scales the
/// picture up, which is lighter on the GPU.
nonisolated struct WantedScreen: Equatable {
    var pointsWidth: Int
    var pointsHeight: Int
    var pixelsWidth: Int
    var pixelsHeight: Int
    /// The scaling the machine is asked to set: 200 for Sharp, 100 for Standard.
    var scalingPercent: Int

    /// The smallest and largest screens a machine is asked for, in pixels.
    static let leastPixels = CGSize(width: 640, height: 400)
    static let mostPixels = CGSize(width: 7680, height: 4320)

    static func wanted(points: CGSize, sharp: Bool) -> WantedScreen {
        let factor = sharp ? 2 : 1
        // Even sizes only: guests' display modes and video encoders do not take odd ones.
        func even(_ value: CGFloat) -> Int { Int(value.rounded(.down)) & ~1 }
        let width = min(max(even(points.width) * factor, Int(leastPixels.width)), Int(mostPixels.width))
        let height = min(max(even(points.height) * factor, Int(leastPixels.height)), Int(mostPixels.height))
        return WantedScreen(
            pointsWidth: width / factor, pointsHeight: height / factor,
            pixelsWidth: width, pixelsHeight: height, scalingPercent: sharp ? 200 : 100)
    }

    /// "1180 × 696 points, 2360 × 1392 pixels" for the window's subtitle and the note.
    var text: String {
        String(localized: "\(String(pointsWidth)) × \(String(pointsHeight)) points, \(String(pixelsWidth)) × \(String(pixelsHeight)) pixels")
    }
}

/// A machine's screen preferences, kept by the app (not in the machine's file): whether its size
/// follows its window, and whether it is drawn Sharp or Standard on a Retina display.
nonisolated enum ScreenPrefs {
    static func followsKey(_ machine: String) -> String { "screenFollowsWindow." + machine }
    static func sharpKey(_ machine: String) -> String { "screenSharp." + machine }

    static func follows(_ machine: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: followsKey(machine)) as? Bool ?? true
    }

    static func sharp(_ machine: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: sharpKey(machine)) as? Bool ?? true
    }
}
