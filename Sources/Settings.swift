import AppKit

/// 一个快捷键组合
struct HotKeyCombo: Equatable {
    var keyCode: UInt16
    var modifierFlags: NSEvent.ModifierFlags

    var display: String { KeyCodeMap.display(keyCode: keyCode, flags: modifierFlags) }
    var carbonModifiers: UInt32 { KeyCodeMap.carbonModifiers(modifierFlags) }
}

/// 全局设置：截图/文字识别快捷键与输出偏好，持久化到 UserDefaults
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard
    private enum Key {
        static let quickCode = "quickKeyCode";   static let quickMods = "quickKeyMods"
        static let normalCode = "normalKeyCode";  static let normalMods = "normalKeyMods"
        static let fullScreenCode = "fullScreenKeyCode"; static let fullScreenMods = "fullScreenKeyMods"
        static let windowCaptureCode = "windowCaptureKeyCode"; static let windowCaptureMods = "windowCaptureKeyMods"
        static let ocrCode = "ocrKeyCode"; static let ocrMods = "ocrKeyMods"
        static let pinCode = "pinKeyCode";   static let pinMods = "pinKeyMods"
        static let copyCode = "copyKeyCode"; static let copyMods = "copyKeyMods"
        static let saveCode = "saveKeyCode"; static let saveMods = "saveKeyMods"
    }

    /// 默认值：快捷模式 ⌥A、正常模式 ⌥S、全屏 ⌥4、窗口 ⌥5、文字识别 ⌥3
    private static let defaultQuick  = HotKeyCombo(keyCode: 0, modifierFlags: .option) // ⌥A
    private static let defaultNormal = HotKeyCombo(keyCode: 1, modifierFlags: .option) // ⌥S
    private static let defaultFullScreen = HotKeyCombo(keyCode: 21, modifierFlags: .option) // ⌥4
    private static let defaultWindowCapture = HotKeyCombo(keyCode: 23, modifierFlags: .option) // ⌥5
    private static let defaultOCR = HotKeyCombo(keyCode: 20, modifierFlags: .option)  // ⌥3
    // 工具栏快捷键默认 1 / 2 / 3（无修饰键），键码 18/19/20
    private static let defaultPin  = HotKeyCombo(keyCode: 18, modifierFlags: [])
    private static let defaultCopy = HotKeyCombo(keyCode: 19, modifierFlags: [])
    private static let defaultSave = HotKeyCombo(keyCode: 20, modifierFlags: [])

    var quick: HotKeyCombo {
        get { read(Key.quickCode, Key.quickMods) ?? Self.defaultQuick }
        set { write(newValue, Key.quickCode, Key.quickMods) }
    }

    var normal: HotKeyCombo {
        get { read(Key.normalCode, Key.normalMods) ?? Self.defaultNormal }
        set { write(newValue, Key.normalCode, Key.normalMods) }
    }

    var fullScreen: HotKeyCombo {
        get { read(Key.fullScreenCode, Key.fullScreenMods) ?? Self.defaultFullScreen }
        set { write(newValue, Key.fullScreenCode, Key.fullScreenMods) }
    }

    var windowCapture: HotKeyCombo {
        get { read(Key.windowCaptureCode, Key.windowCaptureMods) ?? Self.defaultWindowCapture }
        set { write(newValue, Key.windowCaptureCode, Key.windowCaptureMods) }
    }

    var ocr: HotKeyCombo {
        get { read(Key.ocrCode, Key.ocrMods) ?? Self.defaultOCR }
        set { write(newValue, Key.ocrCode, Key.ocrMods) }
    }

    // 工具栏快捷键（截图模式内）
    var pinKey: HotKeyCombo {
        get { read(Key.pinCode, Key.pinMods) ?? Self.defaultPin }
        set { write(newValue, Key.pinCode, Key.pinMods) }
    }
    var copyKey: HotKeyCombo {
        get { read(Key.copyCode, Key.copyMods) ?? Self.defaultCopy }
        set { write(newValue, Key.copyCode, Key.copyMods) }
    }
    var saveKey: HotKeyCombo {
        get { read(Key.saveCode, Key.saveMods) ?? Self.defaultSave }
        set { write(newValue, Key.saveCode, Key.saveMods) }
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

    /// 保存目录（默认桌面）
    var saveDirectory: URL {
        get {
            if let p = d.string(forKey: "saveDirectory") { return URL(fileURLWithPath: p) }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
        set { d.set(newValue.path, forKey: "saveDirectory") }
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
