// Checks the phone page's crypto against CryptoKit, so a change on either side
// that would silently break pairing fails here instead.
//   node --test Tests/PhoneWeb
import assert from "node:assert/strict";
import test from "node:test";
import { accessToken, displayCode, linkKey, openMessage, sealCommand } from "../../Apps/PhoneWeb/pairing.js";

const secret = "ABCDEFGHJKLMNPQR";

// Sealed by CryptoKit with the same derivation as `LinkCrypto`.
const sealedByMac = "N2ZR/Mqyd0r85+kVw1Z1CIzSu+JTNIABsCEyhVNN4NfQhAUURqFKECVbueS3PPiVz3FS/rfRuZy2Mknc9kW+p3yiY8vCxPev7+XFPKnGHytEzz3y8deUMBXQBhoWJEOiTKD/Aa+r+dxdoUs=";

test("derives the same access token and verify code as the Mac", () => {
  assert.equal(accessToken(secret), "4a099f35d45817680869f1a76cff31dc5f92e31548c87ab4e1475a909d8f0879");
  assert.equal(displayCode(secret), "785656");
});

test("opens a message sealed by CryptoKit", () => {
  assert.deepEqual(openMessage(sealedByMac, linkKey(secret)), {
    type: "notice",
    detail: "hello from the mac",
    sentAt: "2026-09-17T10:00:00Z",
  });
});

test("refuses messages sealed for another secret or garbled", () => {
  assert.equal(openMessage(sealedByMac, linkKey("ZZZZZZZZZZZZZZZZ")), null);
  assert.equal(openMessage("not base64!", linkKey(secret)), null);
});

test("seals commands the way the Mac expects", () => {
  const key = linkKey(secret);
  const first = sealCommand("disarm", key, new Date("2026-09-17T10:00:00.456Z"));
  const second = sealCommand("disarm", key, new Date("2026-09-17T10:00:00.456Z"));
  assert.notEqual(first, second, "each command needs a fresh nonce and id");

  const envelope = openMessage(first, key);
  assert.equal(envelope.command, "disarm");
  assert.equal(envelope.sentAt, "2026-09-17T10:00:00Z", "Swift rejects fractional seconds");
  assert.match(envelope.id, /^[0-9a-f]{32}$/);
});
