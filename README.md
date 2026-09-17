# crookcooked

Open-source tamper deterrence for macOS, with encrypted evidence delivery to an iPhone. It watches for input, charger removal, new USB devices, and sustained camera-scene changes while the genuine macOS lock screen is active. The microphone is never used. The alarm is loud by default; quiet mode keeps every sensor running and sends the alert silently.

## Install

Download the latest `crookcooked-mac.zip` from [Releases](../../releases/latest), unzip it, move `Crookcooked.app` to Applications, then Control-click it and choose **Open** the first time. macOS 14 or newer is required.

To get alerts and evidence on your iPhone, run the [relay](docs/RELAY.md) somewhere your phone can reach, enter its address in the Mac app, and scan the QR code with the iPhone Camera app. The link opens a web page served by the relay; there is nothing to install on the phone.

## Develop

```sh
swift run CrookcookedCoreChecks
swift test
swift build --target CrookcookedMac
(cd relay && npm ci && npm test)
```

Run `./scripts/build-mac-app.sh` for a local Mac app or `./scripts/package-mac-release.sh` for the release ZIP. Relay setup and release instructions are in [`docs/`](docs/).

This is a deterrence and evidence tool, not a physical lock. Review [`SECURITY.md`](SECURITY.md) before exposing a relay to the internet. Licensed under [MIT](LICENSE).
