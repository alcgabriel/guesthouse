# Remote view

Remote view lets another device on your network see and use a Windows machine through remoteman's viewer: a laptop on the sofa, a phone, another PC. It is a preview, and it is off for every machine until you switch it on.

It works on a Linux host and on a Windows host, which differ in a few things: [On a Windows host](#on-a-windows-host) says how. What follows is the Linux host.

On a Linux host the machine's own window stays as it is. remoteman's host runs in Windows beside Guesthouse's display driver, and a device that connects gets a screen of its own.

## What it needs

- A Windows machine made by Guesthouse, with its agent working and an up-to-date display driver. An older driver's take-over script would take remoteman's screen for Guesthouse's, so the switch says to update the driver first.
- remoteman's viewer on the other device, on the same network as this PC.

## Switching it on

Open the machine's settings, go to the Network page and turn on Allow viewing from other devices, or run `guesthouse-vm set NAME remote-view on`. A running machine gets remoteman's host at once, and a stopped one at its next start. The first time, Guesthouse downloads remoteman's host installer, checked against the version it was built for, and installs it in Windows. That makes the machine's picture blink for about two seconds. It is only installed again when that version changes. From remoteman 0.1.9 its host looks for updates by itself. Guesthouse switches that off in Windows (`set updates off`) and brings a newer remoteman itself, when Guesthouse is updated. If that doesn't take, it's written in the log and tried again at the next start, and viewing works anyway.

The machine gets a port of its own on this PC, from 7792 to 7899, which stays the same. Guesthouse announces the machine on the network under its name, so remoteman's viewer lists it.

## Pairing a device

Press Pair a New Device. In remoteman on the other device, add a computer and enter the address shown, or pick the machine from the list. The device waits, and its name and a six-digit code appear in Guesthouse. Check that the code matches the one on the device, then press Accept. Pairing closes after one device, or when its time is up.

A new device can see the screen and use the mouse and keyboard. Its clipboard and file transfers are off until you switch them on for it in the list of devices. Remove takes a device off the list, and it has to pair again.

## Switching it off

Turning the switch off closes pairing, turns every device away and stops listening on the network. Paired devices stay paired for when it is switched on again.

## What to know

- Only devices you accepted here can connect. Anyone on the same network can ask to pair while pairing is open.
- While a device shows the machine on its screen only (remoteman's "only" placement), the machine's own window here has no picture until that device leaves.
- Windows in the machine doesn't lock when a device connects. A paired device lands on the open desktop.
- On an NVIDIA card, the card's memory clock is held up while a device streams, so pictures arrive sooner. It costs the card's idle power. [The card's memory clock](nvidia.md#the-cards-memory-clock-while-a-device-views-the-machine) says how to turn it off.

## On a Windows host

A Windows guest on a Windows host has remoteman's host already, as it shows the machine's own screen with it, so nothing is installed when the switch goes on and there is no display driver to update. The service does the work, and the Windows app asks it.

- **Where.** The Windows app has no Remote View group yet. Until it does, ask the service from a command line, as below.
- **One device at a time.** remoteman's host in a Windows guest serves one device at a time. A device that connects takes the screen from the machine's own window, which goes blank, and the app says which device is viewing. Open screen takes the screen back, and the device loses its picture.
- **The address.** Devices use this PC's address and the machine's port, from 7792 to 7899, which stays the same. The service passes them on to the guest, whose own port is 7791. The machine is announced on the network by its name through Windows' own responder, so remoteman's viewer lists it. If its name is taken on this PC already, it isn't listed, and the address and port still work.
- **Pairing.** Open pairing for a time (two minutes unless asked, up to an hour). The device connects and waits; its name and six-digit code show. Check the code on the device, then accept or decline. Pairing closes after one device, or when the time is up. While it is open, the machine's clipboard and file sharing pause, the machine's own window's included, so a new device never has them; they come back when pairing closes, and the new device's own stay off until you switch them on for it.
- **Off.** Turning the switch off closes pairing, stops listening on this PC, takes the firewall rule and the announcement away, and the device viewing loses its picture. It never turns remoteman off in the guest, as that would cut the machine's own window too. Paired devices stay paired. There is no Disconnect for the device viewing, for the same reason: remoteman's own one cuts whichever device has the screen. Open screen takes it back.
- **The guest's firewall.** At every start the guest lets only this PC reach remoteman's port, so a device can't go round the service, its switch or its firewall rule to the guest's own address, which matters most when the machine is bridged onto your network. A machine from before this has its rules narrowed at its first start with the new service.
- **Shared and bridged.** Both are supported. On the shared network devices reach the guest only through this PC. A bridged guest has an address on your network, and this PC's own address there is what the guest lets in; if this PC's address on that network changes while the machine runs, other devices can't view it until the machine starts again, and the app says so. Bridged has not been tried on a real network yet.

From a command line, with the service running, in a checkout of Guesthouse's source:

```powershell
cargo run -p guesthouse-control --example ask -- '{"ask":"share","name":"NAME","on":true}'
cargo run -p guesthouse-control --example ask -- '{"ask":"share","name":"NAME","pairing":true}'
cargo run -p guesthouse-control --example ask -- '{"ask":"remote_view","name":"NAME"}'
cargo run -p guesthouse-control --example ask -- '{"ask":"pair_accept","name":"NAME"}'
cargo run -p guesthouse-control --example ask -- '{"ask":"device_allow","name":"NAME","fingerprint":"FP","what":"clipboard","on":true}'
cargo run -p guesthouse-control --example ask -- '{"ask":"device_revoke","name":"NAME","fingerprint":"FP"}'
cargo run -p guesthouse-control --example ask -- '{"ask":"share","name":"NAME","on":false}'
```

`remote_view` answers where it stands: the port, the devices, a device waiting with its code, and which device has the screen. `pair_decline` and `pair_close` turn a waiting device away and close pairing. [docs/windows-host.md](windows-host.md#viewing-from-other-devices) has how it works.
