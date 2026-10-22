# OpenRemote

OpenRemote turns a phone into a wireless virtual Xbox 360 controller. It is a host for the PC and a controller app for the phone, with on-screen sticks, triggers, buttons, and a d-pad. Layouts — Standard, Lefty, or custom — are arranged on the phone, stored locally, and can be shared as an XML file. The iOS and Android apps read each other's layout files.

<img width="276" height="597" alt="1" src="https://github.com/user-attachments/assets/d99c6c2a-e736-4e82-be9d-a8900d98cca0" />
<img width="597" height="276" alt="2" src="https://github.com/user-attachments/assets/642c00ed-6249-499c-9658-947c1ae158b6" />

## Where it runs

The same design applies to every platform. Linux and Windows can present a gamepad to games; macOS cannot yet. The controller app runs on iOS 26 and on Android 8.0 or later.

| Platform | Role | Now |
| --- | --- | --- |
| Linux | Host | Works. Needs a writable `/dev/uinput`, or `sudo`. |
| Windows | Host | New, not yet tested on real hardware. Needs the [ViGEmBus](https://github.com/nefarius/ViGEmBus/releases/latest) driver. |
| macOS | Host | Builds for Apple Silicon. Exits, because there is no pad backend yet. |
| iOS | Controller | Works. Unsigned IPA, bundle ID `ru.relya.openremote`. |
| Android | Controller | Works. APK signed with the debug key, application ID `ru.relya.openremote`. |

## Build

Go builds the host. The iOS app needs [xtool](https://github.com/xtool-org/xtool). The Android app needs JDK 17 or later and the Android SDK, found through `ANDROID_HOME` (`just android` falls back to `~/Android/Sdk`) or `android/local.properties`; the Gradle wrapper downloads the rest. Results go to `dist/`.

| Command | File |
| --- | --- |
| `just` or `just linux` | `dist/openremote-linux-amd64` |
| `just windows` | `dist/openremote-windows-amd64.exe` |
| `just macos` | `dist/openremote-macos-arm64` |
| `just ios` | `dist/OpenRemote.ipa` |
| `just android` | `dist/OpenRemote.apk` |


## Run

```bash
./dist/openremote-linux-amd64
./dist/openremote-linux-amd64 -addr 0.0.0.0:1337
```

On Windows, install [ViGEmBus](https://github.com/nefarius/ViGEmBus/releases/latest) once, then run `openremote-windows-amd64.exe`. Allow it through Windows Firewall on private networks when asked, or the phone cannot reach it. Games see an Xbox 360 pad through XInput. ViGEmBus is retired upstream, but its last release (1.22) still installs and works.

The terminal shows the QR code and `ip:port`. Scan it in the app, or type the address. On Android, an `openremote://ip:port` link also opens the app and connects. One phone owns the pad. When it disconnects, the pad returns to rest.
