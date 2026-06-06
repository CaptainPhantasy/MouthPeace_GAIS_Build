import Foundation

/// UserDefaults-backed persistence for the hotkey binding.
enum HotKeyStore {
    private static let key = "MouthPeace.HotKey.v1"

    static func load() -> HotKey? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }

    static func save(_ hk: HotKey) {
        guard let data = try? JSONEncoder().encode(hk) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
