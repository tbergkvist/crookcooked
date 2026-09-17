import Foundation

public final class ConfigurationStore {
    private let defaults: UserDefaults
    private let secrets: SecretStore
    private let key = "crookcooked.configuration.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.secrets = SecretStore()
    }

    public func load() -> CrookcookedConfiguration {
        guard let data = defaults.data(forKey: key),
              var value = try? JSONDecoder().decode(CrookcookedConfiguration.self, from: data)
        else {
            var safe = CrookcookedConfiguration.standard
            safe.pairingSecret = secrets.load() ?? safe.pairingSecret
            save(safe)
            return safe
        }
        if value.pairingSecret.isEmpty {
            value.pairingSecret = secrets.load() ?? PairingSecret.generate()
        } else {
            // Migrate early development builds that stored this in UserDefaults.
            secrets.save(value.pairingSecret)
            save(value)
        }
        return value
    }

    public func save(_ configuration: CrookcookedConfiguration) {
        secrets.save(configuration.pairingSecret)
        var redacted = configuration
        redacted.pairingSecret = ""
        guard let data = try? JSONEncoder().encode(redacted) else { return }
        defaults.set(data, forKey: key)
    }
}
