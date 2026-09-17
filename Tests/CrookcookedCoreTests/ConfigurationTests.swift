import Foundation
import Testing

@testable import CrookcookedCore

/// Defaults are a safety surface: a build that silently enables sound, or that
/// loses a privacy default while decoding an older preferences blob, is a bug
/// the owner only discovers in public.
@Suite("Configuration defaults and migration")
struct ConfigurationTests {
    @Test("The shipped default is a loud alarm")
    func loudByDefault() {
        // An alarm nobody hears deters nobody; quiet is a deliberate choice.
        #expect(CrookcookedConfiguration.standard.audibleAlarm)
    }

    @Test("Quiet mode silences the alarm and nothing else")
    func quietModeStillProtects() {
        let quiet = CrookcookedConfiguration.quiet

        #expect(!quiet.audibleAlarm)
        #expect(quiet.recordEvidence)
        #expect(quiet.cameraMovementDetection)
        #expect(quiet.faceAttentionWarning)
    }

    @Test("Standard defaults keep evidence and warnings on")
    func protectiveDefaults() {
        let safe = CrookcookedConfiguration.standard

        #expect(safe.recordEvidence)
        #expect(safe.cameraMovementDetection)
        #expect(safe.faceAttentionWarning)
        #expect(safe.triggerThreshold == 70)
    }

    @Test("The lock screen avatar is on by default")
    func avatarOnByDefault() {
        #expect(CrookcookedConfiguration.standard.lockScreenAvatar)
    }

    @Test("Turning the avatar off is remembered")
    func avatarOptOutIsHonoured() throws {
        // Preferences written before the avatar existed should still get it, but
        // someone who switched it off must not have it come back on upgrade.
        let decoded = try JSONDecoder().decode(
            CrookcookedConfiguration.self,
            from: Data(#"{"lockScreenAvatar":false}"#.utf8)
        )

        #expect(!decoded.lockScreenAvatar)
    }

    @Test("Arming gives you five seconds to walk away")
    func armingDelayIsFiveSeconds() {
        #expect(CrookcookedConfiguration.standard.armingDelaySeconds == 5)
    }

    @Test("An empty payload decodes to the shipped defaults")
    func emptyPayloadIsSafe() throws {
        let decoded = try JSONDecoder().decode(
            CrookcookedConfiguration.self,
            from: Data("{}".utf8)
        )

        #expect(decoded.audibleAlarm)
        #expect(decoded.recordEvidence)
        #expect(decoded.faceAttentionWarning)
        #expect(decoded.triggerThreshold == 70)
        #expect(decoded.armingDelaySeconds == 5)
        #expect(decoded.lockScreenAvatar)
    }

    @Test("Preferences from older builds, including the removed relay URL, still decode")
    func legacyPayloadGainsNewDefault() throws {
        let legacy = #"{"audibleAlarm":false,"triggerThreshold":70,"armingDelaySeconds":8,"recordEvidence":true,"cameraMovementDetection":true,"relayURL":"ws://127.0.0.1:8787","pairingSecret":"OLDSECRET"}"#

        let migrated = try JSONDecoder().decode(
            CrookcookedConfiguration.self,
            from: Data(legacy.utf8)
        )

        #expect(migrated.faceAttentionWarning)
        #expect(migrated.pairingSecret == "OLDSECRET")
        #expect(!migrated.audibleAlarm)
    }

    @Test("A deliberate choice of quiet mode survives decoding")
    func explicitQuietIsHonoured() throws {
        // Someone who opted into silence must not be made loud again by an upgrade.
        let decoded = try JSONDecoder().decode(
            CrookcookedConfiguration.self,
            from: Data(#"{"audibleAlarm":false}"#.utf8)
        )

        #expect(!decoded.audibleAlarm)
    }

    @Test("A missing pairing secret decodes to empty rather than a fresh one")
    func absentSecretDecodesEmpty() throws {
        // ConfigurationStore redacts the secret before writing to UserDefaults and
        // restores it from its own file, so decoding must not invent a new one.
        let decoded = try JSONDecoder().decode(
            CrookcookedConfiguration.self,
            from: Data("{}".utf8)
        )

        #expect(decoded.pairingSecret.isEmpty)
    }

    @Test("Encoding and decoding round-trips without drift")
    func roundTripIsStable() throws {
        var original = CrookcookedConfiguration.standard
        original.triggerThreshold = 88
        original.audibleAlarm = false
        original.lockScreenAvatar = false
        original.pairingSecret = "ABCDEFGHJKLMNPQR"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CrookcookedConfiguration.self, from: data)

        #expect(decoded == original)
    }
}

/// Threat kinds cross the wire between the Mac and the phone page.
/// Renaming a raw value silently breaks every already-installed peer.
@Suite("Threat kinds")
struct ThreatKindTests {
    @Test("Wire identifiers are stable")
    func rawValuesAreStable() {
        #expect(ThreatKind.keyboardOrPointer.rawValue == "keyboard_or_pointer")
        #expect(ThreatKind.powerDisconnected.rawValue == "power_disconnected")
        #expect(ThreatKind.usbAttached.rawValue == "usb_attached")
        #expect(ThreatKind.cameraMovement.rawValue == "camera_movement")
        #expect(ThreatKind.remoteRequest.rawValue == "remote_request")
        #expect(ThreatKind.manualTest.rawValue == "manual_test")
    }

    @Test("Every kind has a non-empty title and a usable base score", arguments: ThreatKind.allCases)
    func everyKindIsPresentable(kind: ThreatKind) {
        #expect(!kind.title.isEmpty)
        #expect(kind.baseScore > 0 && kind.baseScore <= 100)
    }

    @Test("A deliberate trigger outranks every passive sensor signal")
    func deliberateTriggersRankHighest() {
        let passive: [ThreatKind] = [
            .keyboardOrPointer, .powerDisconnected, .usbAttached, .cameraMovement,
        ]

        for kind in passive {
            #expect(kind.baseScore < ThreatKind.remoteRequest.baseScore)
            #expect(kind.baseScore < ThreatKind.manualTest.baseScore)
        }
    }

    @Test("An event adopts its kind's base score when none is given")
    func eventInheritsBaseScore() {
        #expect(CrookcookedEvent(kind: .usbAttached).score == ThreatKind.usbAttached.baseScore)
    }
}
