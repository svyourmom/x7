# iOS: building and installing x7 on an iPhone

<!-- Licensed CC BY 4.0 -->

x7 is one Flutter codebase, so the iOS app is the same app as the Android one. What differs is
how it gets onto the phone: Apple only installs apps that carry a signature from an Apple ID, and
this project has no paid developer account. So CI produces an **unsigned** `.ipa`, and you sign
it yourself with one of the routes below.

## What CI gives you

Every push and pull request builds `x7-<version>-build<N>-<sha>-unsigned.ipa` on a macOS runner
(the `unsigned iOS IPA` job in `.github/workflows/build.yml`). Tagged releases attach it next to
the APK on the [Releases page](https://github.com/svyourmom/x7/releases). It is a plain zip of
`Payload/Runner.app` with no code signature.

## Installing

All three routes need an Apple ID. None need a paid developer account.

| route | what you need | how long the install lasts |
|---|---|---|
| **Xcode** | a Mac, Xcode, a free Apple ID | 7 days, then plug in and re-run (free IDs also cap you at 3 sideloaded apps) |
| **AltStore / Sideloadly** | any computer with iTunes/Apple Mobile Device support, a free Apple ID | 7 days; AltStore refreshes automatically while the computer is on the same Wi-Fi |
| **Paid developer account** | 99 USD/yr | TestFlight builds last 90 days; ad-hoc profiles a year |

**Xcode route:** clone the repo, `flutter pub get`, open `ios/Runner.xcworkspace`, select the
Runner target → Signing & Capabilities → pick your Team. If Xcode says the bundle id
`com.svyourmom.x7` is taken, change it to something unique under your own name. Plug in the
iPhone, trust the computer, and Run. On iOS 16+ you must also turn on Settings → Privacy &
Security → Developer Mode on the phone.

**AltStore / Sideloadly route:** download the `-unsigned.ipa` from Releases and open it in the
tool. It re-signs the file with your Apple ID and installs it.

Sideloaded builds are re-signed by *your* Apple ID every time, so unlike the Android debug-key
situation an upgrade installs in place and keeps your settings.

## What is different from Android

- **One permission prompt.** iOS asks once for Bluetooth. There is no location prompt; iOS does
  not need location to scan for BLE devices, so x7 does not ask for it.
- **Device ids look different.** iOS hides Bluetooth MAC addresses and gives each app a private
  UUID per device instead. The Devices picker in Settings shows that UUID. x7 matches devices by
  advertised name and service, so it finds the controller and BMS the same way.
- **Background.** The app declares the `bluetooth-central` background mode so the link stays
  alive if the phone locks during a LAUNCH window. Whether the countdown timer itself keeps
  running while locked has not been verified on an iPhone yet; if it does not, the limiter is
  restored the moment the app comes back to the foreground.

## Building it yourself

`flutter build ios --release --no-codesign` is exactly what CI runs and works on any Mac with
Xcode, no Apple ID needed. `flutter run` on a plugged-in iPhone needs the Team set as above. The
iOS Simulator has no Bluetooth radio, same as the Android emulator, so it can only show the
layout.

Flutter 3.47 wires the native plugins in with Swift Package Manager, so there is no `Podfile`.
One appears only if Swift Package Manager is turned off in `pubspec.yaml` or a plugin without
SPM support is added later; commit it (and `Podfile.lock`) if that happens.

## Known gaps

- The app icon is Flutter's stock icon on iOS. Android's largest icon is 192 px and iOS wants a
  1024 px source, so a proper icon is a separate change.
- Not yet run on an iPhone against a bike. The Bluetooth stack is the same one the Android
  build uses, so the protocol side is expected to work, but treat the first ride as a bench
  test: wheel off the ground, watch the connection dots.
