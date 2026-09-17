# Public repository checklist

The repository is prepared locally. Before announcing it:

- Create the public GitHub repository and push the reviewed worktree.
- In **Settings → Pages**, select GitHub Actions as the source.
- Enable **Private vulnerability reporting** in **Settings → Security**.
- Protect `main` and require the CI checks.
- Review the MIT copyright line and the public project name.
- Create a signed and notarized `vX.Y.Z` release if you want normal double-click installation; otherwise the documented Control-click flow applies.
- Open the deployed project page and test the download on both an Apple silicon and Intel Mac.

No publishing, external account changes, signing, or notarization is performed automatically from this worktree.
