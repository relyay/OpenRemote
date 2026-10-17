# OpenRemote

A host on the computer shows games an Xbox 360 pad. A controller on the phone sends that pad over the LAN.

## Compatibility

| Platform | Role | Status |
| --- | --- | --- |
| Linux | Host | Works |
| Windows | Host | Builds, pad is not implemented |
| macOS | Host | Builds, pad is not implemented |
| iOS | Controller | Works, iOS 26 |
| Android | Controller | Not started |

## Build

Output is in `dist/`.

| Command | Result |
| --- | --- |
| `make` or `make linux` | `dist/openremote-linux-amd64` |
| `make windows` | `dist/openremote-windows-amd64.exe` |
| `make macos` | `dist/openremote-macos-arm64` |
| `make ios` | `dist/OpenRemote.ipa` |

The host needs Go. The iOS app needs [xtool](https://github.com/xtool-org/xtool).

## Run

```bash
./dist/openremote-linux-amd64
./dist/openremote-linux-amd64 -addr 0.0.0.0:1337
```

The host prints a QR code and `ip:port`. The controller scans the code or enters the address. One controller owns the pad.

On Linux, `/dev/uinput` must be writable (`sudo` if it is not). Windows and macOS hosts exit until a pad backend exists. Install `dist/OpenRemote.ipa` to use the iOS controller.
