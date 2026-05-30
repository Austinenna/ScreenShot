import AppKit

/// 设置窗口：配置两种模式的快捷键
final class SettingsWindowController: NSWindowController {
    /// 快捷键变化后回调，让 AppDelegate 重新注册
    var onHotKeysChanged: (() -> Void)?

    private var borderSlider: NSSlider!
    private var borderValueLabel: NSTextField!
    private var savePathField: NSTextField!

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 370),
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
        title.frame = NSRect(x: 20, y: 328, width: 380, height: 22)
        content.addSubview(title)

        // 快捷模式
        let quickLabel = label("快捷模式（截图后直接复制）", size: 13, weight: .regular)
        quickLabel.frame = NSRect(x: 20, y: 282, width: 240, height: 20)
        content.addSubview(quickLabel)

        let quickRec = HotKeyRecorderView(combo: Settings.shared.quick)
        quickRec.frame = NSRect(x: 250, y: 278, width: 150, height: 28)
        quickRec.onChange = { combo in
            Settings.shared.quick = combo
            self.onHotKeysChanged?()
        }
        content.addSubview(quickRec)

        // 正常模式
        let normalLabel = label("正常模式（截图后进入标注）", size: 13, weight: .regular)
        normalLabel.frame = NSRect(x: 20, y: 240, width: 240, height: 20)
        content.addSubview(normalLabel)

        let normalRec = HotKeyRecorderView(combo: Settings.shared.normal)
        normalRec.frame = NSRect(x: 250, y: 236, width: 150, height: 28)
        normalRec.onChange = { combo in
            Settings.shared.normal = combo
            self.onHotKeysChanged?()
        }
        content.addSubview(normalRec)

        let hint = label("点输入框 → 按下组合键（需含 ⌘/⌥/⌃/⇧）。Esc 取消。", size: 11, weight: .regular)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 210, width: 380, height: 18)
        content.addSubview(hint)

        // 分隔线
        let sep = NSBox(frame: NSRect(x: 20, y: 192, width: 380, height: 1))
        sep.boxType = .separator
        content.addSubview(sep)

        // 白色圆角边框开关
        let borderToggle = NSButton(checkboxWithTitle: "为截图添加白色圆角边框",
                                    target: self, action: #selector(toggleBorder(_:)))
        borderToggle.state = Settings.shared.whiteBorder ? .on : .off
        borderToggle.font = .systemFont(ofSize: 13)
        borderToggle.frame = NSRect(x: 20, y: 162, width: 300, height: 22)
        content.addSubview(borderToggle)

        let borderHint = label("开启后，复制 / 保存 / 钉图的截图都会带白边", size: 11, weight: .regular)
        borderHint.textColor = .secondaryLabelColor
        borderHint.frame = NSRect(x: 38, y: 142, width: 380, height: 18)
        content.addSubview(borderHint)

        // 白边宽度滑块
        let widthLabel = label("白边宽度", size: 13, weight: .regular)
        widthLabel.frame = NSRect(x: 38, y: 106, width: 70, height: 20)
        content.addSubview(widthLabel)

        borderSlider = NSSlider(value: Double(Settings.shared.borderWidth),
                                minValue: 0, maxValue: 40,
                                target: self, action: #selector(sliderChanged(_:)))
        borderSlider.frame = NSRect(x: 110, y: 104, width: 230, height: 24)
        content.addSubview(borderSlider)

        borderValueLabel = label("\(Int(Settings.shared.borderWidth)) pt", size: 13, weight: .medium)
        borderValueLabel.alignment = .right
        borderValueLabel.frame = NSRect(x: 346, y: 106, width: 54, height: 20)
        content.addSubview(borderValueLabel)

        updateBorderControlsEnabled()

        // 分隔线
        let sep2 = NSBox(frame: NSRect(x: 20, y: 86, width: 380, height: 1))
        sep2.boxType = .separator
        content.addSubview(sep2)

        // 保存位置
        let saveTitle = label("保存位置（点「保存」时自动存到这里）", size: 13, weight: .regular)
        saveTitle.frame = NSRect(x: 20, y: 56, width: 380, height: 20)
        content.addSubview(saveTitle)

        savePathField = label(Settings.shared.saveDirectory.path, size: 12, weight: .regular)
        savePathField.textColor = .secondaryLabelColor
        savePathField.lineBreakMode = .byTruncatingMiddle
        savePathField.frame = NSRect(x: 20, y: 24, width: 290, height: 22)
        content.addSubview(savePathField)

        let chooseBtn = NSButton(title: "选择…", target: self, action: #selector(chooseSaveDir))
        chooseBtn.bezelStyle = .rounded
        chooseBtn.frame = NSRect(x: 314, y: 20, width: 86, height: 28)
        content.addSubview(chooseBtn)
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

    @objc private func toggleBorder(_ sender: NSButton) {
        Settings.shared.whiteBorder = (sender.state == .on)
        updateBorderControlsEnabled()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let v = sender.doubleValue.rounded()
        Settings.shared.borderWidth = CGFloat(v)
        borderValueLabel.stringValue = "\(Int(v)) pt"
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
