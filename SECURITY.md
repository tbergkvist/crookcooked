# Security policy

Please report vulnerabilities through the repository's private **Security → Report a vulnerability** form. Do not include pairing secrets, camera evidence, signing credentials, or personal data in a public issue.

The supported version is the latest release. Maintainers will acknowledge a report as soon as practical, investigate it privately, and coordinate disclosure after a fix is available.

crookcooked is a deterrence and evidence layer, not a physical lock. A person can still close the lid, disconnect networking, power down, or damage the Mac; a watching phone raises an alarm when a Mac it is watching goes silent, but cannot stop any of that.

The phone connection stays on the local network: the server refuses devices outside the Mac's own subnets and requests that do not address it by IP, which blocks internet access and DNS rebinding. Status, alerts, frames, clips, and commands are encrypted and authenticated with the secret in the QR code, and commands cannot be replayed. The phone page itself is served over plain HTTP, so an attacker actively intercepting a hostile network while the page loads could substitute it; see [`docs/PHONE.md`](docs/PHONE.md). The pairing secret is stored on the Mac in `~/Library/Application Support/crookcooked/pairing-secret`, readable only by your user account (the whole folder, including evidence clips, is owner-only), and in the phone browser's storage.

Anyone holding the pairing secret can disarm or silence the Mac. Use **New code** in the app if a phone is lost or the link was shared.
