import AppKit

/// 一个快捷键组合
struct HotKeyCombo: Equatable {
    var keyCode: UInt16
    var modifierFlags: NSEvent.ModifierFlags

    var display: String { KeyCodeMap.display(keyCode: keyCode, flags: modifierFlags) }
    var carbonModifiers: UInt32 { KeyCodeMap.carbonModifiers(modifierFlags) }
}

/// 全局设置：两种模式的快捷键，持久化到 UserDefaults
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard
    private enum Key {
        static let quickCode = "quickKeyCode";   static let quickMods = "quickKeyMods"
        static let normalCode = "normalKeyCode";  static let normalMods = "normalKeyMods"
    }

    /// 默认值：快捷模式 ⌥A，正常模式 ⌥S
    private static let defaultQuick  = HotKeyCombo(keyCode: 0, modifierFlags: .option) // ⌥A
    private static let defaultNormal = HotKeyCombo(keyCode: 1, modifierFlags: .option) // ⌥S

    var quick: HotKeyCombo {
        get { read(Key.quickCode, Key.quickMods) ?? Self.defaultQuick }
        set { write(newValue, Key.quickCode, Key.quickMods) }
    }

    var normal: HotKeyCombo {
        get { read(Key.normalCode, Key.normalMods) ?? Self.defaultNormal }
        set { write(newValue, Key.normalCode, Key.normalMods) }
    }

    /// 是否给截图加白色圆角边框（默认关闭）
    var whiteBorder: Bool {
        get { d.bool(forKey: "whiteBorder") }
        set { d.set(newValue, forKey: "whiteBorder") }
    }

    /// 白边宽度（点），默认 4
    var borderWidth: CGFloat {
        get { d.object(forKey: "borderWidth") == nil ? 4 : CGFloat(d.double(forKey: "borderWidth")) }
        set { d.set(Double(newValue), forKey: "borderWidth") }
    }

    private func read(_ codeKey: String, _ modsKey: String) -> HotKeyCombo? {
        guard d.object(forKey: codeKey) != nil else { return nil }
        let code = UInt16(d.integer(forKey: codeKey))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: modsKey)))
        return HotKeyCombo(keyCode: code, modifierFlags: mods)
    }

    private func write(_ combo: HotKeyCombo, _ codeKey: String, _ modsKey: String) {
        d.set(Int(combo.keyCode), forKey: codeKey)
        d.set(Int(combo.modifierFlags.rawValue), forKey: modsKey)
    }
}
