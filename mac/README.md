# Guesthouse for macOS

**Rule.** Before adding logic with no OS or hypervisor calls to the Mac core, read `notes/shared-core-moves.md` and build on the shared crate, or shape the Mac's copy like the other hosts' (their names, fields and wording) and add what it is to `notes/mac-app-shared-core-map.md`, so it can be swapped when the crate lands. See `notes/shared-core.md`.

The Mac app, steps 1 to 4 of `notes/guesthouse-macos-app-design.md`: a SwiftUI app on a small Rust core that opens the machine library, starts, stops and shows machines, and sends them the mouse and keyboard. A background agent owns the running machines, so they carry on when the app quits.

## Build

Needs Xcode 27, XcodeGen and Rust with the `aarch64-apple-darwin` target. From this folder:

```sh
./build.sh
```

It runs `build-core.sh`, `xcodegen generate` and `xcodebuild -project Guesthouse.xcodeproj -scheme Guesthouse -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/dd build`. Set GUESTHOUSE_SIGN_IDENTITY to the SHA-1 of your team's Apple Development certificate to sign a development build; unset, the build is ad hoc.

The app lands in `build/dd/Build/Products/Release/Guesthouse.app`, signed ad hoc (or as above) with the hardened runtime and no App Sandbox. The agent is `Contents/MacOS/guesthouse-agent` in it, and its launchd plist `Contents/Library/LaunchAgents/com.ruxn.guesthouse.agent.plist`. `build-core.sh` puts the core in `build/GuesthouseCore.xcframework`; run it again after changing anything in `core/`.

The build compiles `rmframes_sub.c` from `../scripts/mac/rmhost/` where it lives (project.yml points at it), so that folder has to be there.

The core's tests (state machine, messages, the QEMU command line, the agent against a stand-in for QEMU):

```sh
cd core && cargo test --offline
```

## Machines

Each machine is a folder in `~/Library/Application Support/Guesthouse/Machines` with a `machine.json`. The folder's name is the machine's id, so keep it short (it is in the names of the run folder's sockets, which macOS limits to about 100 characters). Everything the machine needs sits in the folder, and a relative path in `machine.json` is inside it:

```json
{
  "name": "Windows 11", "kind": "windows", "cores": 4, "memory_mb": 6144,
  "disk": "win.img",
  "firmware_code": "code.fd", "firmware_vars": "vars.fd",
  "option_rom": "pvgfb.rom",
  "stick": "stick.img",
  "modes": ["1024x768@60"]
}
```

`name`, `kind`, `cores`, `memory_mb` and `disk` are required. `kind` is a label (`windows`, `linux`) but for one thing: a `linux` machine gets QEMU's user-mode network (`-netdev user,id=net -device virtio-net-pci,netdev=net,romfile=` in place of `-nic none`; no option ROM on the card, so QEMU needs no `efi-virtio.rom`) and the scale its desktop should draw at, as the firmware file `opt/com.ruxn.guesthouse/scale` (`2` for Sharp, `1` for Standard, from the machine's screen setting when it starts; `2` when the app is not asked). With `firmware_code` and `firmware_vars` the app can start the machine (`startable`); `option_rom` (the PV device's option ROM), `stick` (a raw FAT image for a USB stick) and `modes` (the device's display modes, the first being the one the ROM starts in; default `640x480@60`, `1024x768@60`, `1280x800@60`, `1920x1080@60`) are optional. A machine started by the app gets its screen and input names made up: `frames` is `guesthouse.<id>` and `qmp` is `input.sock` in its run folder. A machine run some other way can still name them by hand:

```json
{ "frames": "rmhost.frames", "qmp": "/path/to/run/rmhost-qmp.sock" }
```

Two keys are written by the app for viewing from another device (below): `allow_remote_view` (default false) and `remote_port` (chosen once per machine, from 7792 up).

`frames` is the bootstrap name the device publishes its frames under; with it, Open Screen in the toolbar opens the machine's screen. `qmp` is a QMP socket that takes input.

File, New Machine (⌘N) adds a machine from an existing raw disk image plus the firmware code and variables files (and optionally the option ROM): the files are cloned into the machine's folder (APFS clone, a copy where that is not possible), a short folder name is made from the machine's name, and `machine.json` is written as above. Installing Windows from an ISO is not built. The machine's pane has Rename and Remove (the folder goes to the Trash, only while the machine is not running). Machines can still be made by hand. A folder whose `machine.json` can't be read is left out and logged (`log stream --predicate 'subsystem == "com.ruxn.guesthouse"'`).

### The lab's Windows image, by hand

`$M5` is `~/Developer/lab/m5`. Other work uses the lab's own `win.img` and `vars.fd`, so give the app clones (APFS, no extra space until they change), not the originals:

```sh
M5=~/Developer/lab/m5
D=~/Library/Application\ Support/Guesthouse/Machines/win
mkdir -p "$D"
cp -c $M5/.tools/guest/windows/win.img   "$D/win.img"
cp -c $M5/.tools/guest/windows/vars.fd   "$D/vars.fd"
cp -c $M5/.tools/guest/windows/code.fd   "$D/code.fd"
cp -c $M5/build/pvgfb/pvgfb.rom          "$D/pvgfb.rom"
cat > "$D/machine.json" <<'END'
{ "name": "Windows 11", "kind": "windows", "cores": 4, "memory_mb": 6144,
  "disk": "win.img", "firmware_code": "code.fd", "firmware_vars": "vars.fd",
  "option_rom": "pvgfb.rom", "modes": ["1024x768@60"] }
END
```

## Graphics: the protected path

A machine's `graphics` setting in `machine.json` is `guarded` or `qemu`. No other host names this setting yet (`notes/shared-core.md` has nothing on it), so the Mac chose the words. A file without the key is `guarded`: the protected path is what every machine is meant to use, and new machines write it out. `qemu` is QEMU's own device, kept for comparison and for tests. If the programs the protected path needs are not found, Start is off with a sentence saying which, and the app does not fall back to the other path by itself. The Hardware tab changes it while the machine is off ("Protected graphics (recommended)" or "QEMU's own device"); Details shows the path and the programs found.

The protected path follows `win/run.sh` with `WIN_PVG=host` (`core/src/launch.rs`, tested argument by argument; the `-trace` debugging options are left out):

1. The agent starts `guesthouse-pvg-host --socket RUN/host.sock --control RUN/control.sock --frames guesthouse.<id> --modes LIST` (no `--window`), output to `host.out`, pid in `host.pid`, and waits up to five seconds for `host.sock`. If it ends first the start fails with its last output line ("The graphics process stopped before it was ready: ...") and QEMU is never started. This waiting is in a thread, so the app's request is not held up.
2. Then QEMU, with `-M virt,memory-backend=ram -object memory-backend-shm,id=ram,size=<MB>M` first and `-device pvg-fwd,id=pvg,socket=RUN/host.sock[,romfile=ROM]` in place of `apple-gfx-pci`; no `display-modes` and no `frame-export`. The QMP sockets are as before. Then rmhost if sharing is on.
3. They end together. pvg-host leaves by itself when QEMU does; the agent gives it three seconds, asks it, and ends it. If pvg-host dies first the machine fails ("The graphics process ended: ...") and QEMU is stopped. Both are tracked by pid and start time and found again by a new agent; a graphics process found with no QEMU is ended.
4. The control socket also takes `status` (its last line ends in `published N skipped N dropped N failed N`), which the library's graphics counts read, and `modes WxH@60`, which the screen window sends when the screen follows the window (below).

The programs are found like QEMU and rmhost (`core/src/tools.rs`): `pvg-qemu` is the Settings QEMU path, `GUESTHOUSE_PVG_QEMU`, `Contents/Helpers/qemu-system-aarch64`, then the lab's `m5/build/qemu-pvg/qemu/qemu-system-aarch64`; `pvg-host` is `GUESTHOUSE_PVG_HOST`, `Contents/Helpers/guesthouse-pvg-host`, then the lab's `m5/.tools/m4-frame-export/target/release/guesthouse-pvg-host`, both lab paths marked as development conveniences. Each is asked what it can do before it is trusted (`core/src/probe.rs`): the graphics process is run with `--help` and must name `--frames` (the stock build in `build/guesthouse` does not, and is refused with "an older build that cannot publish the screen"); QEMU is asked `-device help` and must list `pvg-fwd`. Note that a QEMU path chosen in Settings is used for both paths, so the rmhost QEMU (no `pvg-fwd`) is refused for the protected one.

A frame name can have up to four readers at once (the publisher serves them all, with eight slots, and tells a late reader the newest frame by itself), so the app's screen and viewing from another device through rmhost work together. The app is one reader however many of its window, preview and thumbnail are showing, because they share one `ScreenSession`. A fifth reader is refused: the screen then says "Four programs are already showing this machine's screen." and asks again every five seconds. `core/tests/readers.rs` runs a viewer through `rmhost serve` and a second reader on one publisher at once.

## The agent

`guesthouse-agent` owns the running machines: it starts QEMU, watches it, asks it to stop, and answers the app. The app is UI only, so a machine goes on when the app quits, and when the agent itself dies. A machine's process is found again by its pid file in `Run/<id>/machine.pid` and its start time (a recycled pid has another start time). It is Swift around the Rust core: the machines, the processes and every message are in the core, where they are tested; Swift only chooses how the app reaches it, because XPC needs Foundation.

The app reaches the agent one of two ways, chosen when it connects, and Settings, General says which one is live:

1. **launchd and XPC (the design's way).** The app registers `Contents/Library/LaunchAgents/com.ruxn.guesthouse.agent.plist` with `SMAppService.agent(plistName:)` and talks to the mach service `com.ruxn.guesthouse.agent`. This works on this Mac with the ad hoc signed app and with a team-signed development build: registration is accepted at once, shows under Login Items, and launchd starts the agent on the first message and again after a crash. Only the app can connect (the agent checks the app's code signing identifier, `com.ruxn.guesthouse`, and the app checks the agent's), which with Developer ID becomes the team and certificate chain.
2. **A detached child and a Unix socket (the fallback).** If registration or the first answer fails, the app starts `guesthouse-agent --socket` itself, in its own session with its output in `agent.log`, and talks to it on `agent.sock` in the Application Support folder. It keeps running after the app quits. One lock file, `agent.lock`, keeps it to one agent.

The switch is `AgentLauncher.preferLaunchd` in `App/AgentLauncher.swift`: on by default, off with `GUESTHOUSE_AGENT=socket` in the environment. Either way the agent leaves by itself ten seconds after nothing is running and nobody is connected; launchd starts it again when needed. To take the agent out of launchd: `Guesthouse.app/Contents/MacOS/Guesthouse --unregister-agent`.

`guesthouse-agent --print-state` prints every machine's state as one line of JSON and leaves, without answering anyone.

### Messages

One JSON object per line, over the socket and over XPC alike (core/src/protocol.rs). Requests carry `"v":1` and an `id` that comes back in the answer:

```
{"v":1,"id":1,"op":"list"}
{"v":1,"id":2,"op":"start","machine":"win","qemu":"/path/to/qemu-system-aarch64"}
{"v":1,"id":3,"op":"shutdown","machine":"win"}
{"v":1,"id":4,"op":"force_off","machine":"win"}
{"v":1,"id":5,"op":"share","machine":"win","on":true,"pairing":false,"rmhost":"/path/to/rmhost"}
{"v":1,"id":6,"op":"pair_accept","machine":"win"}   (also pair_decline, pair_close)
{"v":1,"id":2,"ok":true}   {"v":1,"id":2,"ok":false,"error":"..."}
{"v":1,"event":"state","machine":"win","state":"shutting_down","reason":null,"stalled":false}
{"v":1,"event":"share","machine":"win","state":"listening","port":7792,"fingerprint":"...","pairing":false,"pairing_until_ms":null,"viewer":null,"reason":null}
```

`start` may also carry `rmhost`, and `list` answers with `shares` beside `machines`.

States: `stopped`, `starting` (QEMU is there, its control socket is not yet), `running`, `shutting_down` (`stalled` once it has not worked in time), `failed` (with a one-line `reason`). The rules for moving between them are in `core/src/state.rs`.

## Starting and stopping

- **Start** builds QEMU's command line from `machine.json` (core/src/launch.rs) the way `win/run.sh` does for `WIN_PVG=qemu WIN_RAMFB=no` with `WIN_RMHOST` set: the QEMU's own PV device with frame export under `guesthouse.<id>`, one QMP socket for the agent (`qmp.sock`) and a second for the app's input (`input.sock`), both in `~/Library/Application Support/Guesthouse/Run/<id>/`, with `qemu.log`, `serial.log` and `machine.pid`. The run.sh debug trace (`-trace`, `-D trace.log`) is not passed. The machine is `running` once QEMU answers on its control socket (30 s at most). A QEMU that fails to start, or exits before that, leaves the machine `failed` with the first line it printed as the reason.
- **Shut Down** sends QMP `system_powerdown` and waits for QEMU to exit. After 60 s it marks the shutdown stalled and the card's Force Off turns on.
- **Force Off** sends QMP `quit`, then SIGTERM to the process if it is still there after 3 s.
- A machine that exits by itself (Windows shut down from inside) is `stopped`; a QEMU that dies with a bad status is `failed`.
- Which QEMU runs is found without typing (`core/src/qemu.rs`): the path in Settings, General if there is one, then `GUESTHOUSE_QEMU`, then `Contents/Helpers/qemu-system-aarch64` inside the app, then, as a development convenience only, the lab's `$M5/build/rmhost/qemu-windows/qemu-system-aarch64`. Settings shows which is in use and why. With none, Start is off and the machine's pane says so, with a button to Settings. Nothing is bundled yet.
- The guarded device process (`WIN_PVG=host`) is a later step: `launch.rs` is where it goes.
- Quitting with machines running asks once: Keep Running (the default), Shut Down All, or Cancel, and "Don't ask again" remembers the answer, which Settings, General can change. Opening the app again shows what is running.

### Trying the agent

With the lab's image, once the machine folder above exists and the QEMU is set in Settings (or with `-qemuPath PATH` on the command line): open the app, select Windows 11, Start. The sidebar dot goes amber, then green; Open Screen shows the desktop. Closing the app with Keep Running and opening it again shows the machine running; Shut Down asks Windows to power off.

Without a guest, `core/src/bin/fake_qemu.rs` stands in for QEMU: it takes the same arguments, opens the QMP sockets, answers `system_powerdown` by exiting half a second later and `quit` at once. Words in the disk image's file name pick its odd behaviours: `failstart` fails with a message, `stubborn` ignores the power button, `deaf` ignores `quit` too (only SIGTERM ends it), `selfexit` and `crash` end it after 2 s. The agent's tests use it (`cargo test --offline`), and by hand:

```sh
export GUESTHOUSE_SUPPORT_DIR=/tmp/gh-try         # keep it short: sockets live under it
export GUESTHOUSE_QEMU=$PWD/core/target/aarch64-apple-darwin/release/fake_qemu
export GUESTHOUSE_AGENT=socket                     # launchd's agent does not see this environment
mkdir -p $GUESTHOUSE_SUPPORT_DIR/Machines/win && cd $GUESTHOUSE_SUPPORT_DIR/Machines/win
touch code.fd vars.fd win-plain.img
echo '{"name":"win","kind":"windows","cores":2,"memory_mb":512,"disk":"win-plain.img","firmware_code":"code.fd","firmware_vars":"vars.fd"}' > machine.json
APP=$OLDPWD/build/dd/Build/Products/Release/Guesthouse.app/Contents/MacOS
$APP/Guesthouse --print-states --start win --quit-after 6 -quitBehavior keep   # starting, running
$APP/guesthouse-agent --print-state                                             # win running
$APP/Guesthouse --print-states --shut-down win --quit-after 5                  # shutting_down, stopped
```

`--start`, `--shut-down` and `--force-off NAME`, `--print-states` and `--quit-after SECONDS` act and report without anyone clicking. `GUESTHOUSE_SHUTDOWN_TIMEOUT_MS` and `GUESTHOUSE_START_TIMEOUT_MS` shorten the agent's timeouts.

## The interface

Built to the five mockups of 2026-11-26 (not kept in the repo), with the system's own controls and colours.

- **Library window**: a sidebar of machines, each with a small picture of its screen (refreshed about once a second, only while the machine runs and the window is visible) and its state, and New Machine at the foot. The pane has the toolbar (Start or Shut Down, a More menu with Force Off, Rename, Remove and Show in Finder, and Open Screen) and four tabs.
- **Overview**: the live picture (a few updates a second, and none while the window is hidden or covered), a strip saying showing, size and frames a second, the State card, and cards for processors, memory, disk with a bar of the space used, and the screen mode. A machine that is off shows a calm stopped state with Start.
- **Sharing**: the switch, pairing, how to connect, and the devices (below).
- **Hardware**: processors and memory can be changed while the machine is off (`guesthouse_machine_set_hardware`); screen modes are fixed for now. **Details**: paths, identifier and Show in Finder.
- **Screen window**: state in the title bar, an indicator while the keyboard is in the machine, Send Keys (Ctrl-Alt-Del, Alt-Tab, Alt-F4), full screen, a footer with the release keys and whether another device is viewing, and statistics over the picture (View, Show Statistics, ⌥⌘S; frames a second, frames skipped, size; off by default).
- **One reader per machine.** The publisher serves four readers, so the app keeps its places to one: a machine has one `ScreenSession` (`Library.screenSession(for:)`) that the window, the preview and the thumbnail present from. It reads frames while anyone presents, drives itself with a timer at the slowest pace asked for when no window drives it with its display link, and puts the same IOSurface into each layer's contents: no copy by the CPU.

Not in the mockups' data: "On for" and "Graphics: this Mac's GPU" are left out (the agent does not know when a machine started, and Windows draws into the device's framebuffer, so the sentence would not be true); the device list has Control, not Clipboard, Files and Sound, because rmhost serves video and input only.

## The screen

One window per machine, titled with its name. The picture is a `CALayer` whose contents is the frame's IOSurface, so the window server composites the device's pixels where they are and the app never copies or reads them. The layer fits the picture inside the window keeping its shape, with black bars.

The view's display link shows the newest frame at each refresh. A frame that arrives while another is still waiting replaces it and counts as skipped. The window holds at most two slots: the one on show, and either the next frame or the one that just left the screen. A slot is given back at the next refresh or the next frame, whichever comes first.

When a resize of the window ends, the app works out the pixels that fill it (`App/ScreenSizing.swift`, Sharp twice the points) and gives them to the core (`core/src/screen_size.rs`). For a running machine on the protected path the core sends `modes WxH@60` to its graphics process, the width down to a multiple of 8 and at most 5120 x 2880, at most one a second with the last one winning, and says it was applied only when the graphics process answers `ok`. A Linux guest with our driver takes the new mode; Windows keeps its own for now. QEMU's own device takes no size from the app, and the answer says so. `notes/mac-app-screen-size.md` has the rest.

Without a publisher the window says "No picture yet" and looks again every second. When the publisher goes away it does the same, so a restarted device is picked up by itself. Closing the window detaches the reader and nothing else. The toolbar shows the picture's size and the frames shown and skipped in the last second.

Frames come over rmframes, the Mach channel in `scripts/mac/rmhost/` (its README and `rmframes.h` describe it), not over XPC as the design says: it is what the device side has today.

Why a plain layer and not a `CAMetalLayer`: it needs no drawing code of ours, the window server scales it, and pacing comes from choosing which surface to set at each display refresh. A Metal pass earns its place once the cursor or HDR needs drawing.

## Viewing from another device

The machine's pane has "Allow viewing from other devices", off by default; off means nothing listens. When it is on and the machine is running, the agent runs `rmhost serve` for the machine (`core/src/agent/share.rs`, the command line in `core/src/remote.rs`). rmhost is the lab's `scripts/mac/rmhost/`: it reads the frames the device publishes under `guesthouse.<id>`, encodes them with the hardware encoder, serves a remoteman viewer, and puts the viewer's input into the guest by QMP. It is a separate process on purpose: it links remoteman's core (GPL-3.0-or-later), and nothing of that is linked into the app or the agent.

- Its own QMP socket, `remote.sock` in the run folder, which every machine's QEMU is given. A QMP socket takes one client at a time, so sharing `input.sock` would lock the app's own window out of the keyboard while a device is viewing, or the reverse.
- A port of its own per machine, chosen once (first free UDP port from 7792 up, since remoteman's transport is QUIC and remoteman's own host uses 7791) and kept in `machine.json`. It listens on all interfaces of the Mac; the pane shows the Mac's local address and its `.local` name with the port, the host key's fingerprint, and a Copy Address button.
- A state folder of its own, `remote-view/` in the machine's folder, so the host's identity and the devices it trusts stay the same from run to run.
- Tracked like QEMU: `rmhost.pid` (pid and start time) and `rmhost.log` in the run folder, found again by a new agent. It ends when the machine stops, when the switch goes off, and with the agent's TERM then KILL.
- rmhost is found like QEMU (`core/src/tools.rs`): `GUESTHOUSE_RMHOST`, `Contents/Helpers/rmhost` in the app, then the lab's `m5/build/rmhost/rmhost` as a development convenience. Without it the switch is off with a sentence saying so.
- Pairing is opened on purpose and closes by itself, with no restart and viewers staying connected, and the Mac asks first. "Pair a New Device" makes the agent write `pair open 120` (`PAIRING_SECONDS` in `core/src/remote.rs`; the `share` op may carry `pairing_seconds`, checked against `MIN_PAIRING_SECONDS` and `MAX_PAIRING_SECONDS`, 1 to 3600) to rmhost's standard input, a named pipe `rmhost.in` in the run folder that rmhost holds open for reading and writing, so a later agent can send it lines too and rmhost never sees the end of its input. A new device is held; rmhost prints its name and code (`ShareInfo.pending`), the pane shows them with Accept and Decline (agent ops `pair_accept`, `pair_decline`), and Stop sends `pair_close`. The time counts only while nobody waits. Every change is a line in `rmhost.log` (`win/rmhost/README.md`, "Pairing while it runs"), which the agent turns into the `share` event: `pairing`, `pairing_until_ms`, `pending`, `paired` (cleared when pairing next opens) and `closed_reason` (`paired`, `declined`, `timeout`, `asked`, `other`). A known device is let in while another waits, and then cuts the waiting one off (the core serves one viewer at a time). The trusted devices are `ShareInfo.devices` (as remoteman's `status.devices`: fingerprint, name, connected, permissions); the agent ops `device_allow` (`what`: `input` for control, `clipboard`, `files`, `sound`, `mic`, `camera`), `device_revoke` and `device_drop` write rmhost's `device`, `revoke` and `drop` lines. A newly accepted device starts with clipboard and files off.

`core/tests/share_flow.rs` runs it with no virtual machine: `fake_qemu`, `testsource` under `guesthouse.sh`, the agent starting the real rmhost, and `viewcheck` over 127.0.0.1. It skips when the three are not built.

## Input

With `qmp` set, the window sends the guest a USB tablet's absolute position (0 to 32767 over the picture, not the bars), the left, right and middle buttons, the scroll wheel and keys, by QMP `input-send-event`. Keys go by their place on the keyboard, as QEMU key names (`core/src/keys.rs`); ⌘ is the Windows key. A thread in the core writes to the socket, so a hung guest never holds up the window. A socket path too long for a socket address, as run folders often are, is reached through a short link in the temporary folder.

- The pointer follows the Mac's pointer over the picture whenever the window is in front.
- Clicking the picture captures the keyboard; that click stays the Mac's. Buttons, wheel and keys go to the guest only while captured.
- ⌃⌥ pressed together lets the keyboard go. So does the window losing focus or closing. Each time, every key and button the guest was told is held is let go.
- While captured, ⌘ shortcuts go to the guest too, except ⌃⌘F (full screen). AppKit gives no key-up for a key pressed with ⌘, so the guest gets those as a press and a release at once.
- Not seen by the app, so not sent: ⌘Tab, ⌘Space, Mission Control and ⌃ arrows, ⌥⌘Esc, ⌃⌘Q, screenshots (⇧⌘3, 4, 5), the Fn or Globe key, and the media and brightness keys. Sending them needs an event tap and the Accessibility grant (design section 2), which is not built.
- ⌃⌥ is also VoiceOver's modifier, and the shortcut can't be changed yet.
- The Mac's pointer is not hidden over the picture, so while Windows draws its own pointer both show.

## Trying the screen

With no guest, `testsource` from rmhost publishes a moving 1080p60 picture (`rmhost/build.sh M5_ROOT` builds it into `M5_ROOT/build/rmhost/`). Make a machine that points at it:

```sh
mkdir -p ~/Library/Application\ Support/Guesthouse/Machines/test
cat > ~/Library/Application\ Support/Guesthouse/Machines/test/machine.json <<'END'
{ "name": "Test", "kind": "windows", "cores": 2, "memory_mb": 2048, "disk": "/none",
  "frames": "guesthouse.test", "qmp": "/tmp/guesthouse-test-qmp.sock" }
END
M5_ROOT/build/rmhost/testsource -n guesthouse.test &      # -r 1280x800 changes size halfway
build/dd/Build/Products/Release/Guesthouse.app/Contents/MacOS/Guesthouse --screen Test --print-stats
```

`--screen NAME` opens that machine's screen at launch and `--print-stats` prints its counts once a second:

```
screen Test: size 1920x1080 received 60 shown 60 skipped 0 most held 2 state showing
```

The app and the publisher have to run in the same login session. The QMP socket may be missing: input is dropped until it is there.

The agent sets this up for a machine it starts. For a guest started by hand: `win/run.sh` started with `WIN_PVG=qemu WIN_RMHOST=rmhost.frames` publishes the device's frames under `rmhost.frames` and opens `rmhost-qmp.sock` in the run folder (rmhost's README has the lines). Set `"frames": "rmhost.frames"` and `"qmp": "RUN_DIR/rmhost-qmp.sock"`. That socket takes one client, so the app and `rmhost serve -q` can't both have it.

## What is where

| File | Job |
|---|---|
| `core/src/qemu.rs` | Finding QEMU: Settings, environment, the app's helpers, the lab build. |
| `core/src/create.rs`, `machines_ffi.rs` | Adding and renaming machines (checks, clones, `machine.json`) and their C functions. |
| `core/src/probe.rs`, `agent/guard.rs` | Asking a program what it can do; the graphics process of the protected path: start, wait, watch, end, find again. |
| `core/src/bin/fake_pvg_host.rs` | The stand-in for the graphics process (see `tests/guarded_flow.rs`). |
| `core/src/remote.rs`, `agent/share.rs` | Viewing from another device: the setting, port, rmhost's command line and log, and running it. |
| `Tests/` | Swift tests of the pane's wording (`xcodebuild -scheme GuesthouseTests test`). |
| `core/src/store.rs` | The machine store: reads the machines folder and works out what starting needs. |
| `core/src/state.rs` | A machine's states and the moves between them. |
| `core/src/protocol.rs` | The messages between app and agent. |
| `core/src/launch.rs` | QEMU's command line, as run.sh builds it. |
| `core/src/agent.rs`, `process.rs`, `control.rs` | The agent: starting, watching and stopping QEMU, finding it again, its QMP conversations. |
| `core/src/server.rs`, `agent_api.rs` | The agent's Unix socket and the app's end of it; the C functions for both. |
| `core/src/bin/fake_qemu.rs` | The stand-in for QEMU. |
| `core/tests/agent_flow.rs` | The agent against the stand-in. |
| `Agent/` | The agent program: `main.swift` and the XPC server. |
| `Shared/AgentXPC.swift` | The XPC interface, built into both the app and the agent. |
| `Launchd/` | The agent's launchd plist. |
| `App/AgentLink.swift`, `AgentLauncher.swift`, `AgentModel.swift` | The app's two ways to the agent, registering or starting it, and the states it reports. |
| `App/AppDelegate.swift` | What quitting asks and does. |
| `core/src/lib.rs`, `core/include/guesthouse_core.h` | The core's C interface. Listings cross as JSON. |
| `core/src/input.rs`, `keys.rs` | Input as QMP events: what is held, the tablet's scale, the wheel, key names. |
| `core/src/link.rs` | The QMP socket: handshake, writing, trying again. |
| `core/tests/qmp_input.rs` | Input through the C functions into a stand-in QMP socket. |
| `App/Core.swift`, `GuestInput.swift` | The core's interface in Swift types. |
| `App/Library.swift` | The machines the window shows. |
| `App/LibraryView.swift`, `MachineDetail.swift` | The library window: sidebar and a machine's settings. |
| `App/GuesthouseApp.swift` | Scenes, menus and the About panel. |
| `App/SettingsView.swift`, `NewMachineSheet.swift` | Settings, and the New Machine sheet. |
| `App/ScreenWindow.swift` | A machine's screen window and its toolbar readout. |
| `App/ScreenView.swift` | The picture's layer, the display link, capture, and mouse and keys to the input. |
| `App/ScreenSession.swift` | Picks the frame to show, gives slots back, attaches again. |
| `App/FrameReader.swift` | rmframes' reading side (`rmframes_sub.c`) in Swift. |
| `App/LaunchOptions.swift` | `--screen`, `--print-stats` and the agent options. |

## Licence

Copyright (C) 2026 RUXN LLC and contributors. GPL-2.0-or-later. `rmframes_sub.c` and its headers, compiled in from the lab repo, are MIT.
