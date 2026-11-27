import Foundation
import Testing

struct PresenterPaceTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// What a presenter is given, one step after another: `offered` for a new frame at that
    /// time, `due` for a refresh with none.
    private enum Step {
        case offered(TimeInterval)
        case due(TimeInterval)
    }

    private func given(_ pace: inout PresenterPace, _ steps: [Step]) -> [Bool] {
        steps.map { step in
            switch step {
            case .offered(let at): pace.offered(at: start + at)
            case .due(let at): pace.due(at: start + at)
            }
        }
    }

    @Test func theFirstFrameIsGivenAtOnce() {
        var pace = PresenterPace(interval: 0.2)
        #expect(given(&pace, [.offered(0)]) == [true])
        #expect(!pace.owed)
    }

    @Test func aFrameTooSoonIsOwedAndGivenWhenTheIntervalIsUpWithNoFrameAfterIt() {
        var pace = PresenterPace(interval: 0.2)
        // The guest's last frame comes 50 ms after one given, and then nothing: owed once,
        // given once, when the interval is up.
        let steps: [Step] = [.offered(0), .offered(0.05), .due(0.1), .due(0.2), .due(0.5)]
        #expect(given(&pace, steps) == [true, false, false, true, false])
        #expect(!pace.owed)
    }

    @Test func nothingIsOwedWhenEveryFrameWasGiven() {
        var pace = PresenterPace(interval: 0.2)
        #expect(given(&pace, [.offered(0), .due(1)]) == [true, false])
    }

    @Test func aTimerAPeriodApartIsNotTakenForTooSoon() {
        var pace = PresenterPace(interval: 0.2)
        #expect(given(&pace, [.offered(0), .offered(0.1995)]) == [true, true])
    }

    @Test func aPictureGivenOutsideThePaceClearsWhatWasOwed() {
        var pace = PresenterPace(interval: 0.2)
        #expect(given(&pace, [.offered(0), .offered(0.05)]) == [true, false])
        #expect(pace.owed)
        pace.given(at: start + 0.06)
        #expect(!pace.owed)
        #expect(given(&pace, [.due(1)]) == [false])
    }

    @Test func aPresenterThatWantsEveryFrameIsNeverOwed() {
        var pace = PresenterPace(interval: 0)
        #expect(given(&pace, [.offered(0), .offered(0)]) == [true, true])
        #expect(!pace.owed)
    }
}
