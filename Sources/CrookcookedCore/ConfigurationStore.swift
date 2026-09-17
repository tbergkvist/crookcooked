import Foundation

/// Preferences live in UserDefaults; the pairing secret lives in its own
/// owner-only file.
///
/// The secret deliberately stays out of the Keychain: every ad-hoc-signed build
/// has a new code signature, and macOS then asks for the login password before
/// the app may read its own Keychain item again.
public final class ConfigurationStore {
    private let defaults: UserDefaults
    private let secretURL: URL
    private let key = "crookcooked.configuration.v1"

    public init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("crookcooked", isDirectory: true)
        secretURL = base.appendingPathComponent("pairing-secret")
    }

    public func load() -> CrookcookedConfiguration {
        restrictDirectory()
        var configuration = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(CrookcookedConfiguration.self, from: $0) }
            ?? .standard
        if let stored = loadSecret() {
            configuration.pairingSecret = stored
        } else if configuration.pairingSecret.count < PairingSecret.minimumLength {
            configuration.pairingSecret = PairingSecret.generate()
        }
        save(configuration)
        return configuration
    }

    public func save(_ configuration: CrookcookedConfiguration) {
        saveSecret(configuration.pairingSecret)
        var redacted = configuration
        redacted.pairingSecret = ""
        guard let data = try? JSONEncoder().encode(redacted) else { return }
        defaults.set(data, forKey: key)
    }

    /// Evidence clips and photos of people live under this folder too, so it is
    /// owner-only regardless of who created it first.
    private func restrictDirectory() {
        let directory = secretURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func loadSecret() -> String? {
        guard let value = try? String(contentsOf: secretURL, encoding: .utf8) else { return nil }
        let secret = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return secret.count >= PairingSecret.minimumLength ? secret : nil
    }

    private func saveSecret(_ secret: String) {
        guard loadSecret() != secret else { return }
        let fileManager = FileManager.default
        restrictDirectory()
        try? fileManager.removeItem(at: secretURL)
        fileManager.createFile(atPath: secretURL.path, contents: Data(secret.utf8), attributes: [.posixPermissions: 0o600])
    }
}
