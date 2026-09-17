// Pairing and evidence crypto, mirroring CrookcookedCore in Swift. Kept free of
// DOM access so the relay tests can check it against CryptoKit output.
import { chacha20poly1305 } from "./vendor/ciphers/chacha.js";
import { sha256 } from "./vendor/hashes/sha2.js";

export const minimumSecretLength = 8;
const encoder = new TextEncoder();
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

export const roomID = secret => hex(sha256(encoder.encode(`crookcooked-room:${secret}`)));
export const evidenceKey = secret => sha256(encoder.encode(`crookcooked-evidence:${secret}`));

/// Opens CryptoKit's `ChaChaPoly.SealedBox.combined` (12-byte nonce, ciphertext,
/// 16-byte tag) from base64. Returns null for anything that does not authenticate.
export function openEvidence(base64, key) {
  if (!base64) return null;
  try {
    const combined = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
    return chacha20poly1305(key, combined.subarray(0, 12)).decrypt(combined.subarray(12));
  } catch {
    return null;
  }
}
