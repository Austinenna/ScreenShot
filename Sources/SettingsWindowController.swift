import AppKit

/// 设置窗口：全局快捷键 / 工具栏快捷键 / 外观 / 保存位置
final class SettingsWindowController: NSWindowController {
    /// 全局快捷键变化后回调，让 AppDelegate 重新注册
    var onHotKeysChanged: (() -> Void)?

    private var borderSlider: NSSlider!
    private var borderValueLabel: NSTextField!
    private var savePathField: NSTextField!

    private let W: CGFloat = 440
    private let M: CGFloat = 20            // 左右边距
    private let recX: CGFloat = 270        // 录制控件起始 x
    private let recW: CGFloat = 150

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 576),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "设置"
        self.init(window: win)
        buildUI()
        win.center()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        var y = content.bounds.height - 16   // 从顶部往下排

        // —— 排版辅助 ——
        func header(_ s: String) {
            let l = label(s, size: 13, weight: .semibold)
            l.frame = NSRect(x: M, y: y - 20, width: W - 2 * M, height: 20)
            content.addSubview(l); y -= 28
        }
        func hint(_ s: String) {
            let l = label(s, size: 11, weight: .regular)
            l.textColor = .secondaryLabelColor
            l.frame = NSRect(x: M, y: y - 16, width: W - 2 * M, height: 16)
            content.addSubview(l); y -= 26
        }
        func separator() {
            let box = NSBox(frame: NSRect(x: M, y: y - 1, width: W - 2 * M, height: 1))
            box.boxType = .separator
            content.addSubview(box); y -= 15
        }
        func recorderRow(_ title: String, combo: HotKeyCombo,
                         requiresModifier: Bool, onChange: @escaping (HotKeyCombo) -> Void) {
            let l = label(title, size: 13, weight: .regular)
            l.frame = NSRect(x: M, y: y - 24, width: recX - M, height: 20)
            content.addSubview(l)
            let rec = HotKeyRecorderView(combo: combo)
            rec.requiresModifier = requiresModifier
            rec.frame = NSRect(x: recX, y: y - 28, width: recW, height: 28)
            rec.onChange = onChange
            content.addSubview(rec)
            y -= 38
        }

        // —— 全局快捷键 ——
        header("全局快捷键")
        recorderRow("快捷模式（截图后直接复制）", combo: Settings.shared.quick,
                    requiresModifier: true) { c in
            Settings.shared.quick = c; self.onHotKeysChanged?()
        }
        recorderRow("正常模式（截图后进入标注）", combo: Settings.shared.normal,
                    requiresModifier: true) { c in
            Settings.shared.normal = c; self.onHotKeysChanged?()
        }
        recorderRow("截全屏（直接复制）", combo: Settings.shared.fullScreen,
                    requiresModifier: true) { c in
            Settings.shared.fullScreen = c; self.onHotKeysChanged?()
        }
        recorderRow("截我选中的窗口（直接复制）", combo: Settings.shared.windowCapture,
                    requiresModifier: true) { c in
            Settings.shared.windowCapture = c; self.onHotKeysChanged?()
        }
        hint("点输入框 → 按下组合键（需含 ⌘/⌥/⌃/⇧）。Esc 取消。")
        separator()

        // —— 工具栏快捷键（截图模式内）——
        header("工具栏快捷键（截图模式内，可用单键）")
        recorderRow("钉图", combo: Settings.shared.pinKey,
                    requiresModifier: false) { c in Settings.shared.pinKey = c }
        recorderRow("复制", combo: Settings.shared.copyKey,
                    requiresModifier: false) { c in Settings.shared.copyKey = c }
        recorderRow("保存", combo: Settings.shared.saveKey,
                    requiresModifier: false) { c in Settings.shared.saveKey = c }
        separator()

        // —— 外观：白色圆角边框 ——
        let borderToggle = NSButton(checkboxWithTitle: "为截图添加白色圆角边框",
                                    target: self, action: #selector(toggleBorder(_:)))
        borderToggle.state = Settings.shared.whiteBorder ? .on : .off
        borderToggle.font = .systemFont(ofSize: 13)
        borderToggle.frame = NSRect(x: M, y: y - 22, width: 300, height: 22)
        content.addSubview(borderToggle); y -= 28
        hint("开启后，复制 / 保存 / 钉图的截图都会带白边")

        let widthLabel = label("白边宽度", size: 13, weight: .regular)
        widthLabel.frame = NSRect(x: M + 18, y: y - 22, width: 64, height: 20)
        content.addSubview(widthLabel)
        borderSlider = NSSlider(value: Double(Settings.shared.borderWidth),
                                minValue: 0, maxValue: 40,
                                target: self, action: #selector(sliderChanged(_:)))
        borderSlider.frame = NSRect(x: M + 90, y: y - 24, width: W - (M + 90) - M - 50, height: 24)
        content.addSubview(borderSlider)
        borderValueLabel = label("\(Int(Settings.shared.borderWidth)) pt", size: 13, weight: .medium)
        borderValueLabel.alignment = .right
        borderValueLabel.frame = NSRect(x: W - M - 50, y: y - 22, width: 50, height: 20)
        content.addSubview(borderValueLabel)
        y -= 36
        updateBorderControlsEnabled()
        separator()

        // —— 保存位置 ——
        header("保存位置（点「保存」时自动存到这里）")
        savePathField = label(Settings.shared.saveDirectory.path, size: 12, weight: .regular)
        savePathField.textColor = .secondaryLabelColor
        savePathField.lineBreakMode = .byTruncatingMiddle
        savePathField.frame = NSRect(x: M, y: y - 24, width: W - 2 * M - 100, height: 22)
        content.addSubview(savePathField)
        let chooseBtn = NSButton(title: "选择…", target: self, action: #selector(chooseSaveDir))
        chooseBtn.bezelStyle = .rounded
        chooseBtn.frame = NSRect(x: W - M - 90, y: y - 28, width: 90, height: 28)
        content.addSubview(chooseBtn)
    }

    // MARK: - Actions

    @objc private func toggleBorder(_ sender: NSButton) {
        Settings.shared.whiteBorder = (sender.state == .on)
        updateBorderControlsEnabled()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let v = sender.doubleValue.rounded()
        Settings.shared.borderWidth = CGFloat(v)
        borderValueLabel.stringValue = "\(Int(v)) pt"
    }

    @objc private func chooseSaveDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Settings.shared.saveDirectory
        panel.prompt = "选择"
        panel.beginSheetModal(for: window!) { [weak self] resp in
            if resp == .OK, let url = panel.url {
                Settings.shared.saveDirectory = url
                self?.savePathField.stringValue = url.path
            }
        }
    }

    private func updateBorderControlsEnabled() {
        let on = Settings.shared.whiteBorder
        borderSlider.isEnabled = on
        borderValueLabel.textColor = on ? .labelColor : .tertiaryLabelColor
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
