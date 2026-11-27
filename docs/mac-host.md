# The Mac host

This is the Mac app: `mac/` is the SwiftUI app, `crates/host-mac/` its Rust core. It runs Windows 11 for ARM or Ubuntu on Apple silicon, with the guest drawing on the Mac's GPU.

It is a preview, and some of it isn't here yet. Here is what the app needs that this repo doesn't hold:

- `guesthouse-pvg-host`, the graphics process, and the library it uses to talk to the guest's driver. They come in their own pull requests.
- A QEMU with the `pvg-fwd` device, from a patch that comes with the graphics process.
- A Windows guest driver and its package, signed for testing. The package isn't published, so an install stops at its driver step and offers to go on without it.

The app finds all three through its Settings, an environment variable (`GUESTHOUSE_QEMU`, `GUESTHOUSE_PVG_QEMU`, `GUESTHOUSE_PVG_HOST`, `GUESTHOUSE_RMHOST`), or inside its own bundle.

The graphics process uses three classes of Apple's ParavirtualizedGraphics framework that Apple doesn't declare, as QEMU's patch that lists them does. A macOS update can break them. Guesthouse isn't affiliated with Apple, and the app isn't distributed through the App Store.

See `mac/README.md` for how to build it.
