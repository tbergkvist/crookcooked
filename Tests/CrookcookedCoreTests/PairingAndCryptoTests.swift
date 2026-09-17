import Foundation
import Testing

@testable import CrookcookedCore

/// The pairing secret is the only thing standing between a stranger on the same
/// network and the owner's evidence stream, so what is derived from it must be
/// deterministic across the two devices and must not leak the secret itself.
@Suite("Pairing secrets")
struct PairingSecretTests {
    @Test("Generated secrets use the requested length")
    func respectsLength() {
        #expect(PairingSecret.generate().count == 16)
        #expect(PairingSecret.generate(length: 24).count == 24)
    }

    @Test("Generated secrets never fall below eight characters")
    func enforcesMinimumLength() {
        #expect(PairingSecret.generate(length: 1).count == 8)
        #expect(PairingSecret.generate(length: 0).count == 8)
    }

    @Test("The alphabet omits characters people confuse when reading aloud")
    func alphabetAvoidsAmbiguity() {
        let secret = PairingSecret.generate(length: 512)
        let ambiguous: Set<Character> = ["I", "O", "0", "1"]

        #expect(secret.allSatisfy { !ambiguous.contains($0) })
        #expect(secret.allSatisfy { $0.isUppercase || $0.isNumber })
    }

    @Test("Two generated secrets differ")
    func generatesDistinctSecrets() {
        #expect(PairingSecret.generate() != PairingSecret.generate())
    }

    @Test("The display code is a stable six digits")
    func displayCodeIsStable() {
        let code = PairingSecret.displayCode(from: "ABCDEFGHJKLMNPQR")

        #expect(code.count == 6)
        #expect(code.allSatisfy { $0.isNumber })
        #expect(code == PairingSecret.displayCode(from: "ABCDEFGHJKLMNPQR"))
    }

    @Test("Different secrets show different codes")
    func displayCodeDiscriminates() {
        #expect(
            PairingSecret.displayCode(from: "ABCDEFGHJKLMNPQR")
                != PairingSecret.displayCode(from: "RQPNMLKJHGFEDCBA")
        )
    }

    @Test("The access token is a stable SHA-256 digest")
    func accessTokenIsStable() {
        let token = PairingSecret.accessToken(from: "ABCDEFGHJKLMNPQR")

        #expect(token.count == 64)
        #expect(token.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(token == PairingSecret.accessToken(from: "ABCDEFGHJKLMNPQR"))
    }

    @Test("The access token never contains the secret")
    func accessTokenDoesNotLeakSecret() {
        let secret = "ABCDEFGHJKLMNPQR"

        #expect(!PairingSecret.accessToken(from: secret).contains(secret.lowercased()))
    }

    @Test("Different secrets get different access tokens")
    func accessTokenDiscriminates() {
        #expect(PairingSecret.accessToken(from: "AAAAAAAA") != PairingSecret.accessToken(from: "AAAAAAAB"))
    }
}

/// Everything on the local network is sealed: anyone else on the same Wi-Fi,
/// including a hostile one, must never be able to open a frame or forge a command.
@Suite("Link encryption")
struct LinkCryptoTests {
    private let secret = "ABCDEFGHJKLMNPQR"
    private let plaintext = Data("a still frame of whoever touched the Mac".utf8)

    @Test("Sealed evidence opens again with the same secret")
    func roundTrips() throws {
        let sealed = try LinkCrypto.seal(plaintext, secret: secret)

        #expect(try LinkCrypto.open(sealed, secret: secret) == plaintext)
    }

    @Test("Sealed evidence does not contain the plaintext")
    func ciphertextHidesPlaintext() throws {
        let sealed = try LinkCrypto.seal(plaintext, secret: secret)

        #expect(sealed != plaintext)
        #expect(sealed.range(of: plaintext) == nil)
    }

    @Test("A wrong secret cannot open the evidence")
    func wrongSecretFails() throws {
        let sealed = try LinkCrypto.seal(plaintext, secret: secret)

        #expect(throws: (any Error).self) {
            try LinkCrypto.open(sealed, secret: "RQPNMLKJHGFEDCBA")
        }
    }

    @Test("Tampered ciphertext is rejected rather than silently decoded")
    func tamperingIsDetected() throws {
        var sealed = try LinkCrypto.seal(plaintext, secret: secret)
        sealed[sealed.count - 1] ^= 0xFF

        #expect(throws: (any Error).self) {
            try LinkCrypto.open(sealed, secret: secret)
        }
    }

    @Test("Sealing the same frame twice produces different ciphertext")
    func sealingIsNonDeterministic() throws {
        // ChaChaPoly uses a fresh nonce per seal; identical output would let an
        // observer tell that nothing in view had changed.
        let first = try LinkCrypto.seal(plaintext, secret: secret)
        let second = try LinkCrypto.seal(plaintext, secret: secret)

        #expect(first != second)
    }

    @Test("Empty evidence round-trips")
    func handlesEmptyData() throws {
        let sealed = try LinkCrypto.seal(Data(), secret: secret)

        #expect(try LinkCrypto.open(sealed, secret: secret).isEmpty)
    }
}
