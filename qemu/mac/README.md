# QEMU for the Mac host

The Mac host runs its machines in QEMU on Hypervisor.framework, with the guest's graphics device in a process of its own, `guesthouse-pvg-host`. QEMU needs two changes for that. They're the patches in `patches/`, on QEMU's master at commit `6bf90d4fc5027567cb704d7888f5ec792b4ed75a` (2026-11-24, version 11.1.91).

| Patch | Author | What |
|---|---|---|
| `0001-apple-gfx-latest-macos.patch` | Mohamed Mediouni | "vmapple: apple-gfx: make it work on the latest macOS release", patch 5 of his series "[RFC PATCH v8 00/10] vmapple: making it work on the latest macOS host releases" on qemu-devel, 2026-09-16. It is his patch as he sent it, and it isn't in QEMU yet. macOS 27 removed the old way of handing the framework a guest's memory, and without this patch QEMU's `apple-gfx` doesn't build against the macOS 27 SDK. |
| `0002-pvg-fwd.patch` | s3k000 | `pvg-fwd`, a PCI device that shows the guest what `apple-gfx-pci` shows and forwards its registers and interrupts over a socket to the process that has the device. |

Only patch 5 of that series is here. The others are about how QEMU decodes some guest memory accesses and about its machine for macOS guests. None of these patches is going to QEMU from here.

## Building it

```sh
brew install glib pixman ninja pkgconf
sh qemu/mac/build.sh
sh mac/build-pvg-host.sh
```

`build.sh` fetches that one commit from QEMU's own git, checks it against the commit's hash and its tree's hash before anything else, applies the patches, and builds `qemu-system-aarch64` with Hypervisor.framework, the framework's own device and the network, and none of QEMU's other optional parts. It takes a few minutes. It writes two folders into `target/mac-helpers/`:

- `helpers/` has `qemu-system-aarch64`, and in `lib/` the libraries it links that macOS doesn't have (glib and what glib needs), found by `@loader_path`. `mac/build-pvg-host.sh` puts the graphics process beside it. This is the folder `mac/nightly.sh --helpers` takes.
- `qemu/` has the firmware (`edk2-aarch64-code.fd` and `edk2-aarch64-vars.fd`), QEMU's licences, the firmware's, and `SOURCE.txt`, which names the commit, the patches and the libraries' versions.

They're two folders because codesign refuses an app with plain files in `Contents/Helpers`. The app still looks for the firmware in `pc-bios/` beside QEMU, so it has to learn to look in `Contents/Resources/qemu/` before a signed build carries this.

`--configure-only` stops after QEMU's configure. `QEMU_SLIRP=disabled` builds without the network, if you don't have libslirp and don't want QEMU to fetch it.

The patches are GPL-2.0-or-later, as the parts of QEMU they change are. QEMU itself is under its own licences, in its `COPYING` and `LICENSE`.
