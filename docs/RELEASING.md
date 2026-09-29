# Releasing

1. Run the checks from `CONTRIBUTING.md`.
2. Set `VERSION` and run `./scripts/package-mac-release.sh`. It creates a universal Apple silicon + Intel build.
3. Test the ZIP on a separate Mac before publishing it: install, grant permissions, pair an iPhone by scanning the code, arm from the phone, trigger an alert, and confirm the photo and clip arrive.
4. Push a `vX.Y.Z` tag to GitHub; the release workflow publishes `crookcooked-mac.zip` (containing `crookcooked.app`) and its SHA-256 checksum to GitHub Releases.

The default package is ad-hoc signed, so users must Control-click the app and choose **Open** the first time. Because macOS ties Camera, Input Monitoring, and Accessibility grants to the code signature, users of ad-hoc builds must also grant them again after each update. For ordinary double-click installation and permissions that survive updates, save notarization credentials with `notarytool store-credentials`, then package with both variables set:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: …" \
NOTARY_KEYCHAIN_PROFILE="crookcooked-notary" \
VERSION="X.Y.Z" \
./scripts/package-mac-release.sh
```

The script submits the ZIP to Apple, staples the approved ticket to the app, recreates the ZIP, and writes its checksum.

The Pages workflow deploys `website/`; its download button links directly to the latest release ZIP.
