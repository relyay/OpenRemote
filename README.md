# OpenRemote

OpenRemote turns a phone into a wireless virtual Xbox 360 controller. It is a host for the PC and a controller app for the phone, with on-screen sticks, triggers, buttons, and a d-pad. Layouts — Standard, Lefty, or custom — are arranged on the phone, stored locally, and can be shared as an XML file.

<img width="276" height="597" alt="1" src="https://github.com/user-attachments/assets/d99c6c2a-e736-4e82-be9d-a8900d98cca0" />
<img width="597" height="276" alt="2" src="https://github.com/user-attachments/assets/642c00ed-6249-499c-9658-947c1ae158b6" />

## Where it runs

The same design applies to every platform, but only Linux can present a gamepad to games today, and only iOS has a controller app (iOS 26).

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
