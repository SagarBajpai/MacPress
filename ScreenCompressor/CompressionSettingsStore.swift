import Foundation

/// `UserDefaults` is thread safe but is not declared `Sendable`, so it is carried in a box
/// rather than being sent across isolation boundaries unchecked.
struct ConfigurationDefaults: @unchecked Sendable {
    let storage: UserDefaults

    static let standard = ConfigurationDefaults(storage: .standard)
}

/// Persists the compression configuration so presets and advanced choices survive relaunches.
actor CompressionSettingsStore {
    private let defaults: ConfigurationDefaults
    private let key: String
    private(set) var configuration: CompressionConfiguration

    init(defaults: ConfigurationDefaults = .standard, key: String = CompressionSettingsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
        self.configuration = Self.read(from: defaults.storage, key: key)
    }

    static let defaultKey = "compression.configuration"

    func update(_ configuration: CompressionConfiguration) {
        let normalized = configuration.normalized()
        self.configuration = normalized
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.storage.set(data, forKey: key)
    }

    func resetToDefault() {
        update(.balanced)
    }

    private static func read(from defaults: UserDefaults, key: String) -> CompressionConfiguration {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CompressionConfiguration.self, from: data) else {
            return .balanced
        }
        // A stored configuration may predate a preset or option change.
        return decoded.normalized()
    }
}
