# Linux graphics driver for the Mac host

This is the Linux guest's driver for the Mac host's graphics device, and the package the Mac app installs it with in an Ubuntu guest. With it, Ubuntu on a Mac draws on the Mac's GPU: weston, GNOME or KDE Plasma, GL through Zink, and Vulkan. It's s3k000's work.

## What you should know

- The device is the one macOS's ParavirtualizedGraphics framework gives a machine. Apple doesn't document its protocol. Everything this driver knows about it was seen from outside, on macOS 27.2.1 (26B131), so a macOS update can change it and break the driver. On the host side the graphics process also uses three framework classes Apple doesn't declare, which `docs/mac-host.md` names.
- Guesthouse isn't affiliated with Apple, and the Mac app isn't distributed through the App Store.
- It's early. It has been tried on one Mac, with Ubuntu 26.04 for arm64 on its own kernel (7.0).

## What's here

| Path | What | Licence |
|---|---|---|
| `driver/` | The kernel module `pvg`: the PCI device and its rings, a display through KMS, buffer objects, the device's tasks and objects, submits with fences and sync objects, and the surface mapper | GPL-2.0, as a Linux kernel module |
| `driver/ruxnpvg_proto.h` | The device's numbers, shared with the Windows driver | MIT |
| `uapi/pvg_drm.h` | What a program includes to reach the driver. Our Vulkan driver's bridge in Mesa builds against it | MIT |
| `package/` | The Ubuntu package: DKMS, our Mesa's place beside Ubuntu's, the desktops, `install.sh`, and the scripts that make it | GPL-2.0-or-later, apart from `build-mesa.sh`, `vm-mesa.sh` and `drirc/` (MIT) |

Each file's SPDX line says its licence, and [LICENSE](LICENSE) says it per folder.

## Building the module

It builds out of tree against a kernel's headers. On Ubuntu 26.04 for arm64, from this folder:

```sh
sudo apt install build-essential linux-headers-$(uname -r)
make -C /lib/modules/$(uname -r)/build M=$PWD/driver modules
sudo insmod driver/pvg.ko
```

It only does anything in a Mac host's guest, where the device is. The CI job in `.github/workflows/linux-pvg.yml` builds it this way against Ubuntu 26.04's headers, and once through DKMS, on every change here.

In a guest the package does it with DKMS instead, which builds the module again for every kernel Ubuntu installs, so a kernel update needs nothing from Guesthouse. `package/dkms/dkms.conf` is that setup; the sources go in `/usr/src/pvg-VERSION` with `driver/` and `uapi/` side by side, as here.

## Secure Boot

The module isn't signed. The Mac app's machines have no Secure Boot (QEMU's firmware there has none), so Linux loads it and notes that it taints the kernel. With Secure Boot on, Ubuntu's kernel would refuse it until DKMS's own key is enrolled with `mokutil`, which needs someone at the firmware's screen.

## The package

The app fetches the package by its manifest from `files.ruxn.com/p/guesthouse/`, puts it on a small disk labelled `RUXN`, and a service in the installed system runs `install.sh` from it once for each version. The folder holds:

| File | What |
|---|---|
| `install.sh` | Installs the packages below with what they need from Ubuntu's archive, after checking each file against the manifest |
| `pvg-dkms_V_all.deb` | The module's sources for DKMS, loaded at every start |
| `pvg-mesa_V_arm64.deb` | Our Mesa in `/opt/pvg-mesa`, used on the pvg device only. Ubuntu's Mesa stays and serves everything else |
| `guesthouse-desktop_V_all.deb` | weston on the pvg device at boot, at the scale and with the keyboard layout the app gives |
| `guesthouse-gnome_V_all.deb`, `guesthouse-plasma_V_all.deb` | Ubuntu's GNOME or KDE Plasma in weston's place, when the install asked for one |
| `guesthouse-linux-driver-latest.json` | `{"version": V, "files": [{"name": "guesthouse-linux-driver-V-FILE", "as": FILE, "sha256": HEX}]}` |

`install.sh` runs as root, with the network. On the serial port it says exactly `guesthouse: driver installed`, or `guesthouse: driver failed CODE`, where CODE is `root`, `system`, `files`, `network`, `headers`, `packages`, `module` or `account` (its header says what each means). Its log is `/var/log/guesthouse/driver-install.log`.

`package/make-package.sh` makes the folder. Today it runs on a Mac and builds in an Ubuntu 26.04 arm64 VM, started by the QEMU that `qemu/mac/build.sh` builds:

```sh
PVG_IMAGE=ubuntu-26.04-server-cloudimg-arm64.img sh drivers/linux-pvg/package/vm.sh $PWD make
sh drivers/linux-pvg/package/vm.sh $PWD start 900
sh drivers/linux-pvg/package/vm.sh $PWD ssh sudo sh -s < drivers/linux-pvg/package/vm-packages.sh
sh drivers/linux-pvg/package/vm.sh $PWD stop
PVG_MESA_TREE=../mesa PVG_WAYLAND_PROTOCOLS=wayland-protocols-1.50.tar.xz \
  sh drivers/linux-pvg/package/make-package.sh $PWD target/linux-pvg/package
```

Nothing in it is signed and it holds no key.

### Our Mesa

The Vulkan driver is KosmicKrisp with a bridge to this driver, and GL is Zink over it. That's a branch of Mesa, and it isn't in this repo or public yet, so the package can't be made from public parts alone for now. `build-mesa.sh` and `vm-mesa.sh` are how it's built for the package: no LLVM linked, through glvnd under the vendor name `pvg`, every library with the run path `/opt/pvg-mesa/lib`.
