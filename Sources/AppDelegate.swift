import Cocoa

enum CaptureMode {
    case quick   // 截图后直接复制
    case normal  // 截图后进入标注
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlay: OverlayController?
    private var editor: AnnotationEditorController?
    private var settingsWC: SettingsWindowController?
    private var pins: [PinController] = []   // 持有钉图窗口，防止被释放
    private var isCapturing = false         // 整屏取图期间也阻止重复触发

    private var quickHotKeyID: UInt32?
    private var normalHotKeyID: UInt32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotKeys()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "截图")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let q = Settings.shared.quick.display
        let n = Settings.shared.normal.display
        menu.addItem(withTitle: "快捷截图（直接复制）  \(q)", action: #selector(quickCapture), keyEquivalent: "")
        menu.addItem(withTitle: "标注截图  \(n)", action: #selector(normalCapture), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: - 快捷键

    private func registerHotKeys() {
        if let id = quickHotKeyID { HotKeyManager.shared.unregister(id) }
        if let id = normalHotKeyID { HotKeyManager.shared.unregister(id) }

        let quick = Settings.shared.quick
        quickHotKeyID = HotKeyManager.shared.register(
            keyCode: quick.keyCode, modifiers: quick.carbonModifiers) { [weak self] in
                self?.startCapture(mode: .quick)
        }

        let normal = Settings.shared.normal
        normalHotKeyID = HotKeyManager.shared.register(
            keyCode: normal.keyCode, modifiers: normal.carbonModifiers) { [weak self] in
                self?.startCapture(mode: .normal)
        }
        rebuildMenu()
    }

    // MARK: - 截图流程

    @objc private func quickCapture()  { startCapture(mode: .quick) }
    @objc private func normalCapture() { startCapture(mode: .normal) }

    private func startCapture(mode: CaptureMode) {
        guard !isCapturing, overlay == nil, editor == nil else { return }
        guard #available(macOS 14.0, *) else { print("需要 macOS 14+"); return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }

        // 在激活应用、显示遮罩之前取图，保留其他应用当前打开的菜单。
        isCapturing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCapturing = false }
            guard let snapshot = await CaptureService.capture(screen: screen) else {
                self.notify(text: "截图失败，请检查屏幕录制权限")
                return
            }

            self.overlay = OverlayController(screen: screen, snapshot: snapshot) { [weak self] result in
                guard let self else { return }
                self.overlay = nil
                guard let (image, rect) = result else { return }
                switch mode {
                case .quick:  self.deliverQuick(image: image, scale: screen.backingScaleFactor)
                case .normal: self.openEditor(image: image, globalRect: rect, screen: screen)
                }
            }
            self.overlay?.show()
        }
    }

    // 快捷模式：直接复制
    @MainActor
    private func deliverQuick(image: CGImage, scale: CGFloat) {
        let out = ImageDecorator.decorate(image, scale: scale)
        let pointSize = NSSize(width: CGFloat(out.width) / scale, height: CGFloat(out.height) / scale)
        let nsImage = NSImage(cgImage: out, size: pointSize)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        notify(text: "已复制到剪贴板")
    }

    // 正常模式：进入标注编辑器
    @MainActor
    private func openEditor(image: CGImage, globalRect: CGRect, screen: NSScreen) {
        editor = AnnotationEditorController(
            image: image, globalRect: globalRect, screen: screen,
            onClose: { [weak self] in self?.editor = nil },
            onPin: { [weak self] cg, rect in self?.pin(image: cg, globalRect: rect) })
        editor?.show()
    }

    // 创建一个钉图窗口并持有
    @MainActor
    private func pin(image: CGImage, globalRect: CGRect) {
        let pin = PinController(image: image, globalRect: globalRect) { [weak self] controller in
            self?.pins.removeAll { $0 === controller }
        }
        pins.append(pin)
        pin.show()
    }

    // MARK: - 设置

    @objc private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
            settingsWC?.onHotKeysChanged = { [weak self] in self?.registerHotKeys() }
        }
        settingsWC?.showAndFocus()
    }

    // MARK: - 杂项

    private func notify(text: String) {
        statusItem.button?.title = " " + text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusItem.button?.title = ""
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
