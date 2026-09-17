# Contributing

Issues and pull requests are welcome. Follow the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md), keep changes focused, explain user-visible behavior, and add coverage for protocol or scoring changes.

Before opening a pull request, run:

```sh
swift run CrookcookedCoreChecks
swift test
swift build --target CrookcookedMac
(cd relay && npm ci && npm test)
```

If you have only the Command Line Tools installed rather than Xcode, run
`./scripts/run-tests.sh` instead of `swift test`; it puts Swift Testing on the
search path for you.

These checks do not launch the apps. Do not launch crookcooked, trigger permissions, capture camera input, lock the screen, or enable sound in automated tests. Never commit signing material, APNs keys, pairing secrets, evidence, or `.env` files.

Security issues should be reported privately as described in [`SECURITY.md`](SECURITY.md).
