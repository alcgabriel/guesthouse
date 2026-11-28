import AppKit
import IOSurface
import SwiftUI

/// The guest's screen: a layer whose contents is the frame's IOSurface, so the window server
/// composites the device's pixels as they are, with no copy of ours. The layer fits the picture
/// inside the view keeping its shape, on black.
///
/// Clicking captures the keyboard; ⌃⌥ pressed together lets it go, as does the window losing
/// focus or closing. Every held key and button is let go whenever the keyboard is.
final class ScreenView: NSView {
    private let session: ScreenSession
    private var displayLink: CADisplayLink?
    private var resignObserver: NSObjectProtocol?
    private let presenterID = UUID()

    /// Told the view's size in points when a resize of the window ends, and once when it first has
    /// a size: the app's half of "the screen follows the window".
    var onSizeSettled: ((CGSize) -> Void)?
    private var settledObserver: NSObjectProtocol?
    private var told: CGSize = .zero
    /// The preferences' stamp last seen (see the representable).
    fileprivate var stamp = Int.min

    /// The keys pressed together that let the keyboard go.
    static let releaseShortcut: NSEvent.ModifierFlags = [.control, .option]
    /// The same keys as they are written for a person.
    static let releaseSymbols = "⌃⌥"

    init(session: ScreenSession) {
        self.session = session
        super.init(frame: .zero)
        let picture = CALayer()
        picture.backgroundColor = NSColor.black.cgColor
        picture.contentsGravity = .resizeAspect
        // No fades or slides between frames or on resize.
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer = picture
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Screen of \(session.machineName)"))
        session.addPresenter(presenterID, interval: 0, isWindow: true) { [weak self] surface in
            self?.layer?.contents = surface
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used from a nib")
    }

    override var isFlipped: Bool { true }

    // MARK: Window, display link and scale

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let window else {
            releaseKeyboard()
            return
        }
        let link = displayLink(target: self, selector: #selector(refresh(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseKeyboard() }
        }
        viewDidChangeBackingProperties()
        if let settledObserver { NotificationCenter.default.removeObserver(settledObserver) }
        settledObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tellSize() }
        }
        DispatchQueue.main.async { [weak self] in self?.tellSize() }
    }

    /// Forgets what was told, so the next call tells it again.
    func tellSizeAgain() {
        told = .zero
        DispatchQueue.main.async { [weak self] in self?.tellSize() }
    }

    /// Tells the size if it is not the one last told. A drag is not followed step by step: the
    /// last picture is stretched while it goes, and the machine is told when it stops.
    func tellSize() {
        guard bounds.width > 0, bounds.height > 0, bounds.size != told else { return }
        told = bounds.size
        onSizeSettled?(bounds.size)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    @objc private func refresh(_ link: CADisplayLink) {
        session.refresh()
    }

    /// Stops the display link; the session is stopped by the window.
    func dismantle() {
        displayLink?.invalidate()
        displayLink = nil
        session.removePresenter(presenterID, isWindow: true)
    }

    // MARK: Capture

    override var acceptsFirstResponder: Bool { session.captured }

    private func captureKeyboard() {
        guard session.input != nil, !session.captured else { return }
        session.captured = true
        window?.makeFirstResponder(self)
    }

    private func releaseKeyboard(resigning: Bool = false) {
        guard session.captured else { return }
        session.captured = false
        session.input?.releaseAll()
        if !resigning, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    override func resignFirstResponder() -> Bool {
        releaseKeyboard(resigning: true)
        return true
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    /// The tablet follows the Mac's pointer over the picture, captured or not.
    private func movePointer(_ event: NSEvent) {
        guard let input = session.input, let size = session.pictureSize else { return }
        let point = convert(event.locationInWindow, from: nil)
        input.pointer(x: point.x, y: point.y, viewSize: bounds.size, pictureWidth: size.width, pictureHeight: size.height)
    }

    private func press(_ event: NSEvent, down: Bool) {
        movePointer(event)
        guard session.captured else { return }
        session.input?.button(event.buttonNumber, down: down)
    }

    override func mouseMoved(with event: NSEvent) { movePointer(event) }
    override func mouseDragged(with event: NSEvent) { movePointer(event) }
    override func rightMouseDragged(with event: NSEvent) { movePointer(event) }
    override func otherMouseDragged(with event: NSEvent) { movePointer(event) }

    override func mouseDown(with event: NSEvent) {
        // The click that captures is the Mac's, not the guest's.
        if !session.captured {
            captureKeyboard()
            movePointer(event)
            return
        }
        press(event, down: true)
    }

    override func mouseUp(with event: NSEvent) { press(event, down: false) }
    override func rightMouseDown(with event: NSEvent) { press(event, down: true) }
    override func rightMouseUp(with event: NSEvent) { press(event, down: false) }
    override func otherMouseDown(with event: NSEvent) { press(event, down: true) }
    override func otherMouseUp(with event: NSEvent) { press(event, down: false) }

    override func scrollWheel(with event: NSEvent) {
        guard session.captured else { return super.scrollWheel(with: event) }
        session.input?.scroll(
            dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard session.captured else { return super.keyDown(with: event) }
        if !event.isARepeat { session.input?.key(event.keyCode, down: true) }
    }

    override func keyUp(with event: NSEvent) {
        guard session.captured else { return super.keyUp(with: event) }
        session.input?.key(event.keyCode, down: false)
    }

    override func flagsChanged(with event: NSEvent) {
        guard session.captured else { return super.flagsChanged(with: event) }
        let held = event.modifierFlags.intersection([.control, .option, .command, .shift])
        if held == Self.releaseShortcut {
            releaseKeyboard()
            return
        }
        let flag = Self.modifierFlag(forKey: event.keyCode)
        session.input?.modifier(event.keyCode, flagOn: event.modifierFlags.contains(flag))
    }

    /// While captured, ⌘ shortcuts go to the guest too (⌘ is its Windows key), except ⌃⌘F,
    /// which stays the Mac's full screen. AppKit sends no key-up for a key pressed with ⌘, so
    /// the guest gets each one as a press and a release at once.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard session.captured, window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.control, .option, .command, .shift])
        if modifiers == [.control, .command], event.charactersIgnoringModifiers?.lowercased() == "f" {
            return super.performKeyEquivalent(with: event)
        }
        session.input?.key(event.keyCode, down: true)
        session.input?.key(event.keyCode, down: false)
        return true
    }

    /// The kind of modifier a modifier key sets, by macOS key code.
    private static func modifierFlag(forKey code: UInt16) -> NSEvent.ModifierFlags {
        switch code {
        case 0x38, 0x3C: .shift
        case 0x3B, 0x3E: .control
        case 0x3A, 0x3D: .option
        case 0x37, 0x36: .command
        case 0x39: .capsLock
        default: .function
        }
    }
}

/// The screen view in SwiftUI.
struct ScreenViewRepresentable: NSViewRepresentable {
    let session: ScreenSession
    var onSizeSettled: ((CGSize) -> Void)?
    /// Changes when the screen preferences do, so the size is told again with the new choice.
    var stamp = 0

    func makeNSView(context: Context) -> ScreenView {
        let view = ScreenView(session: session)
        view.onSizeSettled = onSizeSettled
        return view
    }

    func updateNSView(_ view: ScreenView, context: Context) {
        view.onSizeSettled = onSizeSettled
        if view.stamp != stamp {
            view.stamp = stamp
            view.tellSizeAgain()
        }
    }

    static func dismantleNSView(_ view: ScreenView, coordinator: ()) {
        view.dismantle()
    }
}
