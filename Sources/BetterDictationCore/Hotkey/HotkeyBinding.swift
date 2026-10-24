import Foundation

public enum HotkeyKind: String, Codable, Sendable {
    /// 普通键盘事件（keyDown / keyUp）
    case key
    /// 系统定义事件（媒体键 / 专用功能键）
    case systemDefined
}

public struct HotkeyBinding: Codable, Equatable, Sendable {
    public var kind: HotkeyKind
    /// keyCode 或 NX_KEYTYPE
    public var code: Int
    public var label: String

    public init(kind: HotkeyKind, code: Int, label: String) {
        self.kind = kind
        self.code = code
        self.label = label
    }

    public static func key(_ keyCode: Int) -> HotkeyBinding {
        HotkeyBinding(kind: .key, code: keyCode, label: keyName(keyCode))
    }

    public static func systemDefined(_ nxKeyType: Int) -> HotkeyBinding {
        HotkeyBinding(kind: .systemDefined, code: nxKeyType, label: nxKeyName(nxKeyType))
    }

    public static func keyName(_ code: Int) -> String {
        let names: [Int: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
            79: "F18", 80: "F19", 90: "F20",
            49: "Space", 36: "Return", 53: "Esc", 50: "`",
            9: "V", 7: "X", 8: "C", 0: "A", 1: "S", 2: "D", 3: "F",
            4: "H", 5: "G", 6: "Z", 11: "B", 12: "Q", 13: "W", 14: "E",
            15: "R", 16: "Y", 17: "T", 32: "U", 34: "I", 31: "O", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        ]
        return names[code] ?? "Key\(code)"
    }

    public static func nxKeyName(_ type: Int) -> String {
        let names: [Int: String] = [
            0: "VolumeUp", 1: "VolumeDown", 2: "BrightnessUp", 3: "BrightnessDown",
            4: "CapsLock", 5: "Help", 6: "Power", 7: "Mute", 8: "DownArrow",
            9: "UpArrow", 10: "NumLock", 11: "ContrastUp", 12: "ContrastDown",
            13: "LaunchPanel", 14: "Eject", 15: "VideoMirror",
            16: "PlayPause", 17: "NextTrack", 18: "PreviousTrack",
            19: "FastForward", 20: "Rewind", 21: "IlluminationUp",
            22: "IlluminationDown", 23: "IlluminationToggle",
        ]
        return names[type] ?? "NXKey(\(type))"
    }
}
