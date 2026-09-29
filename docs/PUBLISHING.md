# Public repository checklist

Before making the repository public:

- Review the files and Git history for private material; ignore rules do not remove committed files.
- Review the README and matching website copy.
- In **Settings → Pages**, select GitHub Actions as the source.
- Enable **Private vulnerability reporting** in **Settings → Security**.
- Protect `main` and require the CI checks.
- Review the MIT copyright line and the public project name.
- Create a signed and notarized `vX.Y.Z` release if you want normal double-click installation; otherwise the documented Control-click flow applies.
- Test the GitHub Release download on both an Apple silicon and Intel Mac, including pairing an iPhone on home Wi-Fi and over Personal Hotspot.

No publishing, external account changes, signing, or notarization is performed automatically from this worktree.
