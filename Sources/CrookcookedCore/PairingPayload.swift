import Foundation

/// Everything the phone needs to join the Mac's room, packed into one web link so
/// the iPhone's own Camera app can open it — no app to install.
///
/// The relay serves the phone page at its own address, so the link is the relay
/// URL with `ws`/`wss` swapped for `http`/`https`. The secret travels in the
/// fragment (`#k=…`), which browsers never send to a server.
public struct PairingPayload: Equatable, Sendable {
    /// Matches `PairingSecret.generate()`, which never drops below eight characters.
    public static let minimumSecretLength = 8

    public let relayURL: String
    public let secret: String

    public init(relayURL: String, secret: String) {
        self.relayURL = relayURL
        self.secret = secret
    }

    /// `https://relay.example.com/#k=SECRET`, or an empty string when the relay URL is invalid.
    public var encoded: String {
        guard let relay = RelayEndpoint.validatedURL(from: relayURL),
              var components = URLComponents(url: relay, resolvingAgainstBaseURL: false)
        else { return "" }
        components.scheme = components.scheme == "wss" ? "https" : "http"
        if components.path.isEmpty { components.path = "/" }
        components.query = nil
        components.fragment = "k=\(secret)"
        return components.url?.absoluteString ?? ""
    }

    /// False when the relay address only works on the Mac itself, so a phone
    /// scanning the code would open a page that can never load.
    public var isReachableFromPhone: Bool {
        guard let host = RelayEndpoint.validatedURL(from: relayURL)?.host?.lowercased() else { return false }
        return !["localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0"].contains(host)
    }

    /// Returns `nil` for anything that is not a pairing link.
    /// A scanner points at whatever happens to be in frame, so an unreadable or
    /// unrelated code must fail rather than half-configure the phone.
    public static func decode(_ raw: String) -> PairingPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let fragment = components.fragment,
              fragment.hasPrefix("k=")
        else { return nil }

        let secret = String(fragment.dropFirst(2))
        components.scheme = scheme == "https" ? "wss" : "ws"
        components.fragment = nil
        components.query = nil
        if components.path == "/" { components.path = "" }

        guard let relay = components.url.flatMap({ RelayEndpoint.validatedURL(from: $0.absoluteString) }),
              secret.count >= minimumSecretLength
        else { return nil }

        return PairingPayload(relayURL: relay.absoluteString, secret: secret)
    }
}
