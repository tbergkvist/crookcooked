// Link crypto, mirroring CrookcookedCore in Swift. Free of DOM access so
// Tests/PhoneWeb can check it against CryptoKit output.
//
// The page is served over plain HTTP on the local network, where browsers do not
// expose WebCrypto, so the primitives come from the vendored noble libraries.
import { chacha20poly1305 } from "./vendor/noble-ciphers/chacha.js";
import { randomBytes } from "./vendor/noble-ciphers/utils.js";
import { sha256 } from "./vendor/noble-hashes/sha2.js";

export const minimumSecretLength = 8;
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const hex = bytes => [...bytes].map(value => value.toString(16).padStart(2, "0")).join("");

/// Matches `PairingSecret.displayCode`: djb2 over Unicode scalars with UInt64
/// wrap-around, shown as six digits.
export function displayCode(secret) {
  let value = 5381n;
  for (const character of secret) {
    value = ((value << 5n) + value + BigInt(character.codePointAt(0))) & 0xffffffffffffffffn;
  }
  return String(value % 1000000n).padStart(6, "0");
}

/// Matches `PairingSecret.accessToken`.
export const accessToken = secret => hex(sha256(encoder.encode(`crookcooked-access:${secret}`)));

/// Matches `LinkCrypto`'s key derivation.
export const linkKey = secret => sha256(encoder.encode(`crookcooked-link:${secret}`));

const toBase64 = bytes => btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(""));
const fromBase64 = text => Uint8Array.from(atob(text), character => character.charCodeAt(0));

/// Opens CryptoKit's `ChaChaPoly.SealedBox.combined` (12-byte nonce, ciphertext,
/// 16-byte tag). Returns null for anything that does not authenticate.
export function open(sealed, key) {
  try {
    return chacha20poly1305(key, sealed.subarray(0, 12)).decrypt(sealed.subarray(12));
  } catch {
    return null;
  }
}

/// Decodes one server-sent event from the Mac into its message object.
export function openMessage(base64, key) {
  try {
    const plain = open(fromBase64(base64), key);
    return plain ? JSON.parse(decoder.decode(plain)) : null;
  } catch {
    return null;
  }
}

/// Seals a `CommandEnvelope` for the Mac, in CryptoKit's combined layout.
export function sealCommand(command, key, now = new Date()) {
  const envelope = {
    id: hex(randomBytes(16)),
    command,
    // Swift's `.iso8601` strategy rejects fractional seconds.
    sentAt: now.toISOString().replace(/\.\d+Z$/, "Z"),
  };
  const nonce = randomBytes(12);
  const sealed = chacha20poly1305(key, nonce).encrypt(encoder.encode(JSON.stringify(envelope)));
  const combined = new Uint8Array(nonce.length + sealed.length);
  combined.set(nonce);
  combined.set(sealed, nonce.length);
  return toBase64(combined);
}
