# OpenRemote

OpenRemote is a gamepad that lives on two devices. The computer pretends to have an Xbox 360 controller plugged in. The phone is the thing you actually hold. They talk over the local network, and the game never has to know that the pad is not sitting on the desk.

You start the host, it prints a QR code, and the phone joins by scanning it or by typing the address. From there the phone is the controller: face buttons, sticks, triggers, a d-pad, and the layouts you arrange yourself. Standard keeps the usual Xbox arrangement. Lefty mirrors the clusters for the other hand. Your own layouts stay on the phone and can be passed around as an XML file.

<img width="276" height="597" alt="1" src="https://github.com/user-attachments/assets/d99c6c2a-e736-4e82-be9d-a8900d98cca0" />
<img width="597" height="276" alt="2" src="https://github.com/user-attachments/assets/642c00ed-6249-499c-9658-947c1ae158b6" />

## Where it runs

The idea is the same on every platform. The pad that games can see exists today only on Linux. The controller you can install today is the iOS app, and it needs iOS 26.

| Platform | Role | Now |
| --- | --- | --- |
| Linux | Host | Works. Needs a writable `/dev/uinput`, or `sudo`. |
| Windows | Host | Builds. Exits, because there is no pad backend yet. |
| macOS | Host | Builds for Apple Silicon. Same limit as Windows. |
| iOS | Controller | Works. Unsigned IPA, bundle ID `ru.relya.openremote`. |
| Android | Controller | Not started. |

## Build

Go builds the host. The iOS app needs [xtool](https://github.com/xtool-org/xtool). Results go to `dist/`.

| Command | File |
| --- | --- |
| `just` or `just linux` | `dist/openremote-linux-amd64` |
| `just windows` | `dist/openremote-windows-amd64.exe` |
| `just macos` | `dist/openremote-macos-arm64` |
| `just ios` | `dist/OpenRemote.ipa` |

## Run

```bash
./dist/openremote-linux-amd64
./dist/openremote-linux-amd64 -addr 0.0.0.0:1337
```

The terminal shows the QR code and `ip:port`. One phone owns the pad. When it disconnects, the pad returns to rest.

Install `dist/OpenRemote.ipa` with your usual sideload tool. The phone screens are portrait. The pad itself is landscape.
