# Security policy

Please report vulnerabilities through the repository's private **Security → Report a vulnerability** form. Do not include pairing secrets, camera evidence, signing credentials, or personal data in a public issue.

The supported version is the latest release. Maintainers will acknowledge a report as soon as practical, investigate it privately, and coordinate disclosure after a fix is available.

crookcooked is a deterrence and evidence layer, not a physical lock. A person can still close the lid, disconnect networking, power down, or damage the Mac. The self-hosted relay should be placed behind TLS and a firewall; use `wss://` outside a trusted local network. Camera evidence is end-to-end encrypted, but connection metadata, status, event type, and push tokens are visible to the relay process.
