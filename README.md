# crookcooked

Open-source tamper deterrence for macOS, with encrypted alerts and camera evidence on your iPhone. While the genuine macOS lock screen is active, it watches for keyboard and trackpad input, charger removal, new USB devices, and the Mac being moved (seen as the whole camera view shifting). Someone merely looking at the Mac is shown their photo on the lock screen but does not set off the alarm. The microphone is never used. The alarm is loud by default, forced to the built-in speakers at full volume, and can be silenced from the phone; quiet mode keeps every sensor running and sends the alert silently.

## Install

Download the latest `crookcooked-mac.zip` from [Releases](../../releases/latest), unzip it, move `crookcooked.app` to Applications, then Control-click it and choose **Open** the first time. macOS 14 or newer is required.

## Connect your iPhone

With the iPhone on the same Wi-Fi as the Mac, point the iPhone Camera app at the QR code in crookcooked and tap the link. There is no iPhone app, account, or server: the Mac serves the phone page itself, and everything after the page loads is encrypted with the secret in the QR code. See [`docs/PHONE.md`](docs/PHONE.md) for how it works and what to do on Wi-Fi that keeps devices apart.

## Develop

```sh
swift run CrookcookedCoreChecks
swift test
swift build --target CrookcookedMac
node --test Tests/PhoneWeb/*.test.mjs
```

Run `./scripts/build-mac-app.sh` for a local app in `dist/` or `./scripts/package-mac-release.sh` for the release ZIP. Release steps are in [`docs/RELEASING.md`](docs/RELEASING.md).

This is a deterrence and evidence tool, not a physical lock; [`SECURITY.md`](SECURITY.md) describes its limits. Licensed under [MIT](LICENSE).
