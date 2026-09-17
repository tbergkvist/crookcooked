import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";

// The browser loads the crypto libraries from /vendor/, which the server maps
// to node_modules. Resolve the same way here.
register("data:text/javascript," + encodeURIComponent(`
  export async function resolve(specifier, context, next) {
    const match = specifier.match(/^\\.\\/vendor\\/(ciphers|hashes)\\/(.+)$/);
    return next(match ? "@noble/" + match[1] + "/" + match[2] : specifier, context);
  }
`), import.meta.url);

const { displayCode, evidenceKey, openEvidence, roomID } = await import("../public/pairing.js");

// Produced by CryptoKit with the same derivation as CrookcookedCore.
const secret = "ABCDEFGHJKLMNPQR";
const sealed = "lHqYcWHWqEOdHso0qpAE8KqqnZn6z9Jcb5NF/Cb4fc2jIjpZOeyB9RA93Aag2uCL1Mcb";

test("derives the same room ID and verify code as the Mac", () => {
  assert.equal(roomID(secret), "6103906e5d3128cb418c89607c6fa60de3d98d009ad7295f1819b095d934e3fe");
  assert.equal(displayCode(secret), "785656");
});

test("opens evidence sealed by CryptoKit", () => {
  const plain = openEvidence(sealed, evidenceKey(secret));
  assert.equal(new TextDecoder().decode(plain), "jpeg bytes from the mac");
});

test("refuses evidence sealed for another secret", () => {
  assert.equal(openEvidence(sealed, evidenceKey("ZZZZZZZZZZZZZZZZ")), null);
  assert.equal(openEvidence("not base64!", evidenceKey(secret)), null);
});
