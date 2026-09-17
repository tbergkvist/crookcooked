# Contributing

Issues and pull requests are welcome. Follow the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md), keep changes focused, explain user-visible behavior, and add coverage for protocol, crypto, or scoring changes.

Before opening a pull request, run:

```sh
swift run CrookcookedCoreChecks
swift test
swift build --target CrookcookedMac
node --test Tests/PhoneWeb/*.test.mjs
```

If you have only the Command Line Tools installed rather than Xcode, run
`./scripts/run-tests.sh` instead of `swift test`; it puts Swift Testing on the
search path for you.

## Layout

- `Sources/CrookcookedCore`: configuration, threat scoring, crypto, and the phone-link protocol. No UI or sockets, so it is fully testable.
- `Apps/Mac`: the SwiftUI app, sensors, camera, lock verification, and the local server for the phone (`PhoneLinkServer.swift`).
- `Apps/PhoneWeb`: the page the iPhone opens. Plain HTML, CSS, and JavaScript modules with vendored crypto; no build step.
- `Tests/PhoneWeb`: checks that the page's crypto matches CryptoKit.
- `scripts/make-app-icon.swift`: regenerates the app icon and web icons.

These checks do not launch the app. Do not launch crookcooked, trigger permissions, capture camera input, lock the screen, or enable sound in automated tests. Never commit signing material, pairing secrets, evidence, or `.env` files.

Security issues should be reported privately as described in [`SECURITY.md`](SECURITY.md).
