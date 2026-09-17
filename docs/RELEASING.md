# Releasing

1. Run the checks from `CONTRIBUTING.md`.
2. Set `VERSION` and run `./scripts/package-mac-release.sh`. It creates a universal Apple silicon + Intel build.
3. Test the ZIP on a separate Mac before publishing it.
4. Tag the commit as `vX.Y.Z`; the release workflow publishes `crookcooked-mac.zip` and its SHA-256 checksum.

The default package is ad-hoc signed, so users must Control-click the app and choose **Open** the first time. For ordinary double-click installation, save notarization credentials with `notarytool store-credentials`, then package with both variables set:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: …" \
NOTARY_KEYCHAIN_PROFILE="crookcooked-notary" \
VERSION="X.Y.Z" \
./scripts/package-mac-release.sh
```

The script submits the ZIP to Apple, staples the approved ticket to the app, recreates the ZIP, and writes its checksum.

The project page is deployed from `website/` by the Pages workflow. On GitHub Pages it derives the repository and latest-release URLs automatically. For a custom domain, set `repositoryURL` in `website/site-config.js`.
