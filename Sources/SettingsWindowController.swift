import AppKit

/// 设置窗口：配置两种模式的快捷键
final class SettingsWindowController: NSWindowController {
    /// 快捷键变化后回调，让 AppDelegate 重新注册
    var onHotKeysChanged: (() -> Void)?

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "设置"
        self.init(window: win)
        buildUI()
        win.center()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = label("快捷键设置", size: 15, weight: .semibold)
        title.frame = NSRect(x: 20, y: 158, width: 380, height: 22)
        content.addSubview(title)

        // 快捷模式
        let quickLabel = label("快捷模式（截图后直接复制）", size: 13, weight: .regular)
        quickLabel.frame = NSRect(x: 20, y: 112, width: 240, height: 20)
        content.addSubview(quickLabel)

        let quickRec = HotKeyRecorderView(combo: Settings.shared.quick)
        quickRec.frame = NSRect(x: 250, y: 108, width: 150, height: 28)
        quickRec.onChange = { combo in
            Settings.shared.quick = combo
            self.onHotKeysChanged?()
        }
        content.addSubview(quickRec)

        // 正常模式
        let normalLabel = label("正常模式（截图后进入标注）", size: 13, weight: .regular)
        normalLabel.frame = NSRect(x: 20, y: 70, width: 240, height: 20)
        content.addSubview(normalLabel)

        let normalRec = HotKeyRecorderView(combo: Settings.shared.normal)
        normalRec.frame = NSRect(x: 250, y: 66, width: 150, height: 28)
        normalRec.onChange = { combo in
            Settings.shared.normal = combo
            self.onHotKeysChanged?()
        }
        content.addSubview(normalRec)

        let hint = label("点输入框 → 按下组合键（需含 ⌘/⌥/⌃/⇧）。Esc 取消。", size: 11, weight: .regular)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 24, width: 380, height: 18)
        content.addSubview(hint)
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        return l
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
