import Foundation
import IOSurface
import Observation
import os

/// One machine's screen: reads its frames, picks the newest at each display refresh, gives
/// slots back, and attaches again when the publisher comes back.
///
/// Slots held: the one on show, a frame waiting for the next refresh, and the one that just
/// left the screen: three at most, and two in practice, since a frame that arrives gives the
/// leaving one back first. The publisher has eight slots for up to four readers. A frame that arrives while another
/// is still waiting replaces it, and the replaced one is skipped and given back at once, so
/// the publisher never waits on the window.
@Observable
final class ScreenSession {
    enum State: Equatable {
        case waiting
        case showing
    }

    /// A frame in one of the slots, and the slot's surface.
    struct Held {
        let generation: UInt32
        let slot: UInt32
        let surface: IOSurfaceRef
        let width: Int
        let height: Int
    }

    let machineName: String
    /// The machine's folder, which names it.
    let machineID: String
    let service: String
    let qmpSocket: String?
    /// The machine's input while the window is open and the machine has a QMP socket.
    private(set) var input: GuestInput?
    /// Whether the window has the keyboard.
    var captured = false
    private(set) var state = State.waiting
    /// The picture's size in pixels, once a frame has been shown.
    private(set) var pictureSize: (width: Int, height: Int)?
    /// Frames shown and skipped in the last whole second.
    private(set) var shownPerSecond = 0
    private(set) var skippedPerSecond = 0
    /// Frames the machine sent in the last whole second, whatever was done with them.
    private(set) var receivedPerSecond = 0
    /// Why the machine's frames are not coming, in words for a person, when the publisher
    /// turned this reader away. Cleared when frames start.
    private(set) var refusedReason: String?

    /// Who is looking at the picture: the screen window, which asks for every refresh, the
    /// machine's preview, and the sidebar's small picture, which ask for a few a second.
    private struct Presenter {
        let interval: TimeInterval
        var last = Date.distantPast
        let show: (IOSurfaceRef?) -> Void
    }

    @ObservationIgnored private var presenters: [UUID: Presenter] = [:]
    /// The screen windows open on this machine, which drive every refresh with their display
    /// link. With none, the session drives itself at the pace of its slowest need.
    private(set) var windowCount = 0
    @ObservationIgnored private var idleTimer: Timer?

    @ObservationIgnored private let reader = FrameReader()
    @ObservationIgnored private var slots: FrameReader.Slots?
    @ObservationIgnored private var shown: Held?
    @ObservationIgnored private var waitingFrame: Held?
    @ObservationIgnored private var leaving: Held?
    @ObservationIgnored private var shownCount = 0
    @ObservationIgnored private var skippedCount = 0
    @ObservationIgnored private var receivedCount = 0
    /// The most slots held at once in this second, for --print-stats.
    @ObservationIgnored private var mostHeld = 0
    @ObservationIgnored private var secondTimer: Timer?
    @ObservationIgnored private var attachTimer: Timer?
    @ObservationIgnored private var running = false

    /// How often to look for the publisher while it is not there.
    private static let attachInterval: TimeInterval = 1

    private let log = Logger(subsystem: "com.ruxn.guesthouse", category: "screen")

    init(machine: Machine, service: String) {
        machineName = machine.name
        machineID = machine.id
        self.service = service
        qmpSocket = machine.qmp
        reader.onSlots = { [unowned self] in newSlots($0) }
        reader.onFrame = { [unowned self] in arrived($0) }
        reader.onRefused = { [unowned self] reason in
            // Not from inside the reader's callback: see FrameReader.close.
            DispatchQueue.main.async { self.publisherRefused(reason) }
        }
        reader.onGone = { [unowned self] in
            // Not from inside the reader's callback: see FrameReader.close.
            DispatchQueue.main.async { self.publisherGone() }
        }
    }

    var heldCount: Int {
        [shown, waitingFrame, leaving].compactMap { $0 }.count
    }

    /// Starts showing the picture to `show`, and starts reading frames if this is the first to
    /// ask. `interval` is the least time between pictures for this presenter (0: every
    /// refresh). A window also opens the machine's input.
    func addPresenter(_ id: UUID, interval: TimeInterval, isWindow: Bool = false, show: @escaping (IOSurfaceRef?) -> Void) {
        presenters[id] = Presenter(interval: interval, show: show)
        Library.shared.screens[machineID] = self
        if isWindow {
            windowCount += 1
            if input == nil, let qmpSocket { input = GuestInput(socket: qmpSocket) }
        }
        if let shown { show(shown.surface) }
        start()
        updateDriver()
    }

    /// Stops showing the picture to `id`, and stops reading when nobody is left.
    func removePresenter(_ id: UUID, isWindow: Bool = false) {
        guard presenters.removeValue(forKey: id) != nil else { return }
        if isWindow {
            windowCount = max(0, windowCount - 1)
            if windowCount == 0 {
                // Lets go of every key and button still held, then closes the socket.
                input?.close()
                input = nil
                captured = false
            }
        }
        if presenters.isEmpty { stop() } else { updateDriver() }
    }

    private func start() {
        guard !running else { return }
        running = true
        secondTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
            MainActor.assumeIsolated { endOfSecond() }
        }
        attach()
    }

    /// Detaches the reader and nothing else.
    private func stop() {
        guard running else { return }
        running = false
        Library.shared.screens[machineID] = nil
        idleTimer?.invalidate()
        idleTimer = nil
        secondTimer?.invalidate()
        attachTimer?.invalidate()
        detach()
        log.info("Screen of \(self.machineName, privacy: .public) detached")
    }

    /// With no window to drive the refreshes, a timer does, no faster than anyone asks.
    private func updateDriver() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard running, windowCount == 0, let interval = presenters.values.map(\.interval).min() else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 0.05), repeats: true) { [unowned self] _ in
            MainActor.assumeIsolated { refresh() }
        }
    }

    private func show(_ surface: IOSurfaceRef?) {
        let now = Date()
        for (id, var presenter) in presenters where now.timeIntervalSince(presenter.last) >= presenter.interval {
            presenter.last = now
            presenters[id] = presenter
            presenter.show(surface)
        }
    }

    /// Called at each display refresh: shows the waiting frame, if there is one, and gives back
    /// the frame that left the screen at the refresh before.
    func refresh() {
        giveBack(&leaving)
        guard let next = waitingFrame else { return }
        waitingFrame = nil
        leaving = shown
        shown = next
        show(next.surface)
        shownCount += 1
        if pictureSize?.width != next.width || pictureSize?.height != next.height {
            pictureSize = (next.width, next.height)
        }
        if state != .showing { state = .showing }
        mostHeld = max(mostHeld, heldCount)
    }

    private func attach() {
        guard running else { return }
        if let reason = reader.open(service: service) {
            log.debug("No screen for \(self.machineName, privacy: .public) yet: \(reason, privacy: .public)")
            attachTimer = Timer.scheduledTimer(withTimeInterval: Self.attachInterval, repeats: false) { [unowned self] _ in
                MainActor.assumeIsolated { attach() }
            }
            return
        }
        log.info("Screen of \(self.machineName, privacy: .public) attached to \(self.service, privacy: .public)")
    }

    private func detach() {
        // Give back what we hold before saying bye, so the publisher has its slots at once.
        giveBack(&waitingFrame)
        giveBack(&leaving)
        giveBack(&shown)
        reader.close()
        slots = nil
        show(nil)
        pictureSize = nil
        state = .waiting
    }

    /// How long to wait before asking again after being turned away.
    private static let retryAfterRefusal: TimeInterval = 5

    /// The publisher has all the readers it serves. Say so, let go, and ask again in a while:
    /// another reader may have left. (Not done for a publisher that went away, which would
    /// ask again at once and loop.)
    private func publisherRefused(_ reason: String) {
        guard running else { return }
        log.info("Screen of \(self.machineName, privacy: .public) refused: \(reason, privacy: .public)")
        shown = nil
        waitingFrame = nil
        leaving = nil
        detach()
        refusedReason = String(localized: "Four programs are already showing this machine's screen.")
        attachTimer = Timer.scheduledTimer(withTimeInterval: Self.retryAfterRefusal, repeats: false) { [unowned self] _ in
            MainActor.assumeIsolated { attach() }
        }
    }

    private func publisherGone() {
        guard running else { return }
        log.info("Screen of \(self.machineName, privacy: .public): publisher went away")
        // Its slots went with it: nothing to give back.
        shown = nil
        waitingFrame = nil
        leaving = nil
        detach()
        attach()
    }

    private func newSlots(_ new: FrameReader.Slots) {
        // Every slot of the old generation counts as given back. The old picture stays on
        // screen until the first frame of the new one.
        waitingFrame = nil
        leaving = nil
        shown = nil
        slots = new
        refusedReason = nil
        log.info("Screen of \(self.machineName, privacy: .public): \(new.surfaces.count) slots of \(new.width)x\(new.height), generation \(new.generation)")
    }

    private func arrived(_ frame: rmf_frame_msg) {
        guard let slots, frame.generation == slots.generation else { return }
        guard Int(frame.slot) < slots.surfaces.count else {
            reader.release(generation: frame.generation, slot: frame.slot)
            return
        }
        receivedCount += 1
        giveBack(&leaving)
        if waitingFrame != nil {
            giveBack(&waitingFrame)
            skippedCount += 1
        }
        waitingFrame = Held(
            generation: frame.generation, slot: frame.slot, surface: slots.surfaces[Int(frame.slot)],
            width: Int(frame.width), height: Int(frame.height))
        mostHeld = max(mostHeld, heldCount)
    }

    private func giveBack(_ held: inout Held?) {
        guard let frame = held else { return }
        held = nil
        reader.release(generation: frame.generation, slot: frame.slot)
    }

    private func endOfSecond() {
        shownPerSecond = shownCount
        skippedPerSecond = skippedCount
        receivedPerSecond = receivedCount
        if LaunchOptions.printStats {
            let size = pictureSize.map { "\($0.width)x\($0.height)" } ?? "none"
            print("screen \(machineName): size \(size) received \(receivedCount) shown \(shownCount) skipped \(skippedCount) most held \(mostHeld) state \(state)")
            fflush(stdout)
        }
        shownCount = 0
        skippedCount = 0
        receivedCount = 0
        mostHeld = heldCount
    }
}
