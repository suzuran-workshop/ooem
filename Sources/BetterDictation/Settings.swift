import Foundation
import BetterDictationCore

enum Settings {
    private static let bindingKey = "hotkey.binding"

    static var binding: HotkeyBinding? {
        get {
            guard let data = UserDefaults.standard.data(forKey: bindingKey) else { return nil }
            return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: bindingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: bindingKey)
            }
        }
    }
}
