import Foundation

/// What the graphics process says about how it is doing.
nonisolated struct GraphicsCounts: Equatable {
    var published: Int
    /// Commands from the guest that the guard refused.
    var refused: Int
    /// The guard marked the device spoiled.
    var spoiled: Bool

    /// A sentence for the State card when the guard refused something, nil when all is well.
    func warning(system: String) -> String? {
        guard refused > 0 || spoiled else { return nil }
        return String(localized: "The graphics guard refused a command from \(system). The screen may be wrong.")
    }
}
