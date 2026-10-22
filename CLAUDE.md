# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OpenRemote turns a phone into a wireless virtual Xbox 360 controller. Three independent codebases share one wire protocol:

- **Host** (Go, repo root + `internal/`): creates a virtual pad and receives input from the phone. Linux uses `/dev/uinput` (`internal/uinput`), Windows uses the ViGEmBus driver (`internal/vigem`), macOS builds but exits. The backend is picked in `pad_linux.go` / `pad_windows.go` / `pad_other.go`, which also hold the OS-specific error texts.
- **iOS controller** (`ios/`, SwiftUI, iOS 26, built with xtool on Linux).
- **Android controller** (`android/`, Kotlin, Jetpack Compose + Material 3 only, minSdk 26).

## Commands

Builds go to `dist/` via `just`:

```bash
just linux            # host (default recipe); also: just windows, just macos
just ios              # cd ios && xtool dev build -c release --ipa
just android          # gradlew assembleRelease; ANDROID_HOME defaults to ~/Android/Sdk
```

Host:

```bash
go vet ./...                 # also with GOOS=windows and GOOS=darwin
go test -race ./...
go test ./internal/protocol -run TestBinaryRoundTrip -v   # single test
./dist/openremote-linux-amd64 -addr 0.0.0.0:1337           # needs writable /dev/uinput or sudo
```

Android (run from `android/`, needs `ANDROID_HOME` or `local.properties` with `sdk.dir`):

```bash
./gradlew testDebugUnitTest lintDebug assembleDebug
./gradlew testDebugUnitTest --tests 'ru.relya.openremote.LayoutXmlTest'   # single test class
```

Lint must pass; `lintDebug` fails the build on errors. Android unit tests are plain JVM tests, which is why layout XML is parsed with SAX (`javax.xml`) rather than Android's `XmlPullParser`.

iOS has no tests; verify with `just ios` (xtool is at `/usr/local/bin/xtool`).

## Wire protocol (shared by all three)

Defined in `internal/protocol/protocol.go`; both phone apps must stay byte-compatible with it.

- A **14-byte little-endian frame** is one full pad snapshot: 4× int16 sticks (positive Y is down), 2× uint8 triggers, uint16 button bits, 2× int8 hat. Button bit order A B X Y LB RB Back Start Guide L3 R3 matches evdev codes of a real Xbox 360 so SDL indices line up. The host applies the *diff* from the previous snapshot, so clients always send the whole pad.
- **WebSocket `/ws`** (hand-written RFC 6455 in `internal/ws`, no dependency) owns the pad. A new connection takes the pad and the old one is closed with **code 4000**, which tells the client *not* to reconnect.
- **UDP on the same port**: `uint16 seq` + frame. Out-of-order packets are dropped by sequence (wraparound via `int16(seq-last)`). While a datagram arrived in the last 300 ms, WebSocket frames are ignored (`udpFresh`), so clients keep a UDP heartbeat running.
- `internal/pad` holds every digital edge for at least 16 ms (`minPulse`) so a quick tap is not lost by games that sample once per frame.
- TCP_NODELAY is set on accept; Nagle would merge a tap's press and release.

`internal/vigem` talks to ViGEmBus with raw `DeviceIoControl` (stdlib `syscall`, no cgo, no ViGEmClient DLL), mirroring `ViGEmClient.cpp`: check version, plug in on the first free serial, wait until ready, then submit full `XUSB_REPORT`s. XInput's stick Y is up-positive, the protocol's is down-positive, so `ReportFrom` flips it. The IOCTL codes and struct layouts live in the untagged `bus.go` so `go test` checks them on Linux; only the I/O is in `device_windows.go`. There is no Windows CI or Wine here: changes to the Windows path are verified with `GOOS=windows go vet ./...` and `just windows` only.

The host prints a QR code of `openremote://ip:port`; both apps parse that, `ws://`/`http(s)://` URLs, or bare `ip:port`.

## Phone apps: parallel structure

The Android app is a port of the iOS app; keep features and persisted formats in sync when changing either.

| Concern | iOS | Android |
| --- | --- | --- |
| Link (WS + UDP, reconnect, 4000) | `Session.swift` | `Session.kt` |
| Pad snapshot + frame encoding, dead zone | `PadSnapshot.swift` | `Pad.kt` |
| Live layout, presets, saved layouts | `LayoutStore.swift`, `LayoutLibrary.swift` | `Layout.kt` |
| Layout XML import/export | `LayoutXML.swift` | `LayoutXml.kt` |
| Settings and their defaults | `AppSettings` in `GamepadView.swift` | `Settings.kt` |
| Pad screen and touch controls | `GamepadView.swift`, `TouchControls.swift` | `ui/Pad.kt`, `ui/PadControls.kt` |
| Navigation / app state | `OpenRemoteApp.swift`, `ShellView.swift` | `AppModel.kt` (ViewModel), `ui/App.kt` |

Things that need several files to understand:

- **Layouts** store control positions as fractions of the pad canvas. While `faceCustom`/`centerCustom` is false, the A/B/X/Y diamond and the Back/Guide/Start row are *computed* from the canvas size in points/dp (fixed gaps 54 and 96) so they keep their shape on any screen; dragging one freezes the whole group. `extras` are additional copies of a control with their own id and a `kind`.
- **The layout XML file format** (`<openremote-layout>` with `<control>` and `<hidden>`) is shared between iOS and Android; files exported on one must import on the other. Saved layouts use the same JSON field names on both.
- **Settings defaults** live in exactly one place per app (`AppSettings.Default` on iOS, `Settings` companion constants on Android); the settings screen, the readers and "reset settings" all use them.
- **Touch input** must fire on first contact with no slop or long-press delay, or quick taps never reach the game (iOS uses custom `UIGestureRecognizer`s; Android uses raw `awaitEachGesture`). Sticks press L3/R3 when a finger rests still for `stickClickTimeout` or on a quick tap.
- A gamepad attached to the phone replaces the touch controls. On Android, gamepad keys are intercepted in `MainActivity.dispatchKeyEvent` before Compose can use them for focus.
- The pad screen is landscape and full screen; the rest of the app is portrait. Android keeps the activity alive across these changes (`configChanges` in the manifest) so the connection is not dropped.

## Conventions

- User-facing text is English and Russian. Go uses `i18n.T(en, ru)` (locale from `LC_ALL`/`LC_MESSAGES`/`LANG`, then the Windows display language); iOS uses `L10n`; Android uses `values/` and `values-ru/` string resources.
- App ID / bundle ID is `ru.relya.openremote` on both platforms. Bump the version in both `ios/Info.plist` and `android/app/build.gradle.kts` (`versionName`, and increment `versionCode`).
- Android release APKs are signed with the debug key for now; release signing is planned for 1.0.
- `PKGBUILD` packages the host only, from a `v<pkgver>` git tag.
- `ios/xtool/` and `android/**/build/` are build output and must not be committed.
