import Foundation

struct RememberedDevice: Codable, Equatable {
    var peripheralIdentifier: UUID
    var displayName: String
    var lastConnectedAt: Date
}

final class RememberedDeviceStore {

    static let shared = RememberedDeviceStore()

    private let defaults: UserDefaults
    private let trainerKey = "rememberedTrainer"
    private let hrmKey = "rememberedHRM"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var trainer: RememberedDevice? {
        get { load(key: trainerKey) }
        set { save(newValue, key: trainerKey) }
    }

    var hrm: RememberedDevice? {
        get { load(key: hrmKey) }
        set { save(newValue, key: hrmKey) }
    }

    func forgetTrainer() {
        defaults.removeObject(forKey: trainerKey)
    }

    func forgetHRM() {
        defaults.removeObject(forKey: hrmKey)
    }

    func forgetAll() {
        forgetTrainer()
        forgetHRM()
    }

    private func load(key: String) -> RememberedDevice? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RememberedDevice.self, from: data)
    }

    private func save(_ device: RememberedDevice?, key: String) {
        if let device, let data = try? JSONEncoder().encode(device) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
