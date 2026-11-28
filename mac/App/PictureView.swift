import AppKit
import IOSurface
import SwiftUI

/// A small, live picture of a machine's screen, for the overview and the sidebar. It is the
/// same IOSurface-backed content the screen window shows, set as a layer's contents and scaled
/// by the window server, so nothing of the picture is copied by the CPU here. It asks the
/// session for a few pictures a second, and nothing at all while its window is hidden,
/// minimised or covered: it then lets go of the session, which stops reading frames when
/// nobody else is looking.
final class PictureView: NSView {
    private let session: ScreenSession
    private let interval: TimeInterval
    private let presenterID = UUID()
    private var attached = false
    private var observers: [NSObjectProtocol] = []

    init(session: ScreenSession, interval: TimeInterval) {
        self.session = session
        self.interval = interval
        super.init(frame: .zero)
        let picture = CALayer()
        picture.backgroundColor = NSColor.black.cgColor
        picture.contentsGravity = .resizeAspect
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer = picture
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Picture of the screen of \(session.machineName)"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used from a nib")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                })
            }
            layer?.contentsScale = window.backingScaleFactor
        }
        update()
    }

    override func viewDidHide() {
        super.viewDidHide()
        update()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        update()
    }

    /// Looks at the session only while the picture can be seen.
    private func update() {
        let visible = window.map { $0.occlusionState.contains(.visible) && !$0.isMiniaturized } ?? false
        let wanted = visible && !isHiddenOrHasHiddenAncestor
        if wanted && !attached {
            attached = true
            session.addPresenter(presenterID, interval: interval) { [weak self] surface in
                self?.layer?.contents = surface
            }
        } else if !wanted && attached {
            detach()
        }
    }

    private func detach() {
        attached = false
        session.removePresenter(presenterID)
    }

    /// Lets go of the session when SwiftUI takes the view away.
    func dismantle() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if attached { detach() }
    }
}

struct PictureViewRepresentable: NSViewRepresentable {
    let session: ScreenSession
    let interval: TimeInterval

    func makeNSView(context: Context) -> PictureView {
        PictureView(session: session, interval: interval)
    }

    func updateNSView(_ view: PictureView, context: Context) {}

    static func dismantleNSView(_ view: PictureView, coordinator: ()) {
        view.dismantle()
    }
}
