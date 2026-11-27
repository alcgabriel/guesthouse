import Foundation

/// When a presenter that wants a picture no more often than `interval` is given one. A frame it
/// is not given, because its last came too short a while before, is owed: it gets the newest
/// picture once its interval is up, whether or not another frame comes. A guest that draws its
/// last frame just after another and then nothing (a desktop that has settled) would otherwise
/// leave the overview's picture on the frame before, which at a start is often black.
struct PresenterPace {
    let interval: TimeInterval
    private(set) var last = Date.distantPast
    private(set) var owed = false

    /// A timer that fires every `interval` does not fire exactly that far apart.
    static let slack: TimeInterval = 0.01

    init(interval: TimeInterval) {
        self.interval = interval
    }

    private func isUp(at now: Date) -> Bool {
        now.timeIntervalSince(last) >= interval - Self.slack
    }

    /// A new frame is there: whether to give it now. If not, a picture is owed.
    mutating func offered(at now: Date) -> Bool {
        guard isUp(at: now) else {
            owed = true
            return false
        }
        last = now
        owed = false
        return true
    }

    /// No new frame: whether to give the picture already on show now, as one owed.
    mutating func due(at now: Date) -> Bool {
        guard owed, isUp(at: now) else { return false }
        last = now
        owed = false
        return true
    }

    /// Given a picture outside the pace: the one on show when it starts looking, or none.
    mutating func given(at now: Date) {
        last = now
        owed = false
    }
}
