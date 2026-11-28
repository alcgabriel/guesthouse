// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import IOSurface

/// A reader of one publisher's frames over the rmframes channel (`rmframes_sub.c`). Everything
/// arrives on the main queue. Each frame's slot stays ours until `release`.
final class FrameReader {
    struct Slots {
        let generation: UInt32
        let width: Int
        let height: Int
        let surfaces: [IOSurfaceRef]
    }

    var onSlots: (Slots) -> Void = { _ in }
    var onFrame: (rmf_frame_msg) -> Void = { _ in }
    var onGone: () -> Void = {}
    /// The publisher has as many readers as it serves and turned this one away. Nothing more
    /// comes; close and try again later.
    var onRefused: (String) -> Void = { _ in }

    private var sub: OpaquePointer?
    /// Keeps this object alive for the C side until `close`.
    private var retained: Unmanaged<FrameReader>?

    /// Looks up `service` and says hello. Returns why it could not, such as no publisher by
    /// that name yet.
    func open(service: String) -> String? {
        close()
        let me = Unmanaged.passRetained(self)
        var callbacks = rmf_sub_callbacks()
        callbacks.ctx = me.toOpaque()
        callbacks.on_slots = { ctx, generation, width, height, count, surfaces in
            MainActor.assumeIsolated {
                let reader = Unmanaged<FrameReader>.fromOpaque(ctx!).takeUnretainedValue()
                let list = (0..<Int(count)).compactMap { surfaces?[$0]?.takeUnretainedValue() }
                reader.delivered(Slots(generation: generation, width: Int(width), height: Int(height), surfaces: list))
            }
        }
        callbacks.on_frame = { ctx, frame in
            MainActor.assumeIsolated {
                let reader = Unmanaged<FrameReader>.fromOpaque(ctx!).takeUnretainedValue()
                if let frame, reader.sub != nil { reader.onFrame(frame.pointee) }
            }
        }
        callbacks.on_gone = { ctx in
            MainActor.assumeIsolated {
                let reader = Unmanaged<FrameReader>.fromOpaque(ctx!).takeUnretainedValue()
                if reader.sub != nil { reader.onGone() }
            }
        }
        callbacks.on_refused = { ctx, reason in
            let text = reason.map { String(cString: $0) } ?? ""
            MainActor.assumeIsolated {
                let reader = Unmanaged<FrameReader>.fromOpaque(ctx!).takeUnretainedValue()
                if reader.sub != nil { reader.onRefused(text) }
            }
        }
        var error = [CChar](repeating: 0, count: 256)
        guard let opened = rmf_sub_open(service, DispatchQueue.main, callbacks, &error, error.count) else {
            me.release()
            return String(decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        sub = opened
        retained = me
        return nil
    }

    func release(generation: UInt32, slot: UInt32) {
        guard let sub else { return }
        rmf_sub_release(sub, generation, slot)
    }

    /// Says bye. Never call it from inside one of the callbacks: the C side may still be
    /// reading messages there, so hop to the next turn of the main queue first.
    func close() {
        guard let sub else { return }
        self.sub = nil
        rmf_sub_close(sub)
        // The C side stops calling us once closed; let go of the reference it held on the
        // next turn, after any callback already under way has returned.
        if let retained {
            self.retained = nil
            DispatchQueue.main.async { retained.release() }
        }
    }

    private func delivered(_ slots: Slots) {
        if sub != nil { onSlots(slots) }
    }
}
