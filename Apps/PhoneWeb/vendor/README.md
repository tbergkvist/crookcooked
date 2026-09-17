# Vendored libraries

The phone page is served over plain HTTP on the local network, where browsers do not expose WebCrypto, so it uses audited pure-JavaScript implementations instead. Files are copied unmodified from npm; licenses are alongside.

- `noble-ciphers/`: `@noble/ciphers` 2.4.0 (ChaCha20-Poly1305)
- `noble-hashes/`: `@noble/hashes` 2.4.0 (SHA-256)

To update, copy the same files from the new package versions and run `node --test Tests/PhoneWeb`.
