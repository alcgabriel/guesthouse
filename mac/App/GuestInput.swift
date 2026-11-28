import Foundation
import GuesthouseCore

/// A machine's input, through the core to its QMP socket. The core keeps track of what is
/// held and never waits on QEMU. Whoever opens one closes it.
final class GuestInput {
    private var handle: OpaquePointer?

    init?(socket: String) {
        guard let handle = guesthouse_input_open(socket) else { return nil }
        self.handle = handle
    }

    /// `x` and `y` from the view's top left, in the same unit as the view's size.
    func pointer(x: Double, y: Double, viewSize: CGSize, pictureWidth: Int, pictureHeight: Int) {
        guesthouse_input_pointer(
            handle, x, y, viewSize.width, viewSize.height, Double(pictureWidth), Double(pictureHeight))
    }

    func button(_ number: Int, down: Bool) {
        guard number >= 0 else { return }
        guesthouse_input_button(handle, UInt32(number), down)
    }

    func scroll(dx: Double, dy: Double, precise: Bool) {
        guesthouse_input_scroll(handle, dx, dy, precise)
    }

    func key(_ code: UInt16, down: Bool) {
        guesthouse_input_key(handle, code, down)
    }

    func modifier(_ code: UInt16, flagOn: Bool) {
        guesthouse_input_modifier(handle, code, flagOn)
    }

    func releaseAll() {
        guesthouse_input_release_all(handle)
    }

    /// Lets go of everything held and closes the socket.
    func close() {
        guesthouse_input_close(handle)
        handle = nil
    }
}
