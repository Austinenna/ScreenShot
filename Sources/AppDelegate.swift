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
        guard overlay == nil, editor == nil else { return } // 防止重入

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }

        overlay = OverlayController(screen: screen) { [weak self] rect in
            self?.overlay = nil
            guard let rect, rect.width > 2, rect.height > 2 else { return }
            self?.captureAndProceed(rect: rect, screen: screen, mode: mode)
        }
        overlay?.show()
    }

    private func captureAndProceed(rect: CGRect, screen: NSScreen, mode: CaptureMode) {
        guard #available(macOS 14.0, *) else { print("需要 macOS 14+"); return }
        // 等遮罩消失再截，避免截进遮罩本身
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task {
                guard let cg = await CaptureService.capture(globalRect: rect, screen: screen) else {
                    print("截图失败"); return
                }
                await MainActor.run {
                    switch mode {
                    case .quick:  self.deliverQuick(image: cg, pointSize: rect.size)
                    case .normal: self.openEditor(image: cg, globalRect: rect, screen: screen)
                    }
                }
            }
        }
    }

    // 快捷模式：直接复制
    @MainActor
    private func deliverQuick(image: CGImage, pointSize: CGSize) {
        let nsImage = NSImage(cgImage: image, size: pointSize)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        notify(text: "已复制到剪贴板")
    }

    // 正常模式：进入标注编辑器
    @MainActor
    private func openEditor(image: CGImage, globalRect: CGRect, screen: NSScreen) {
        editor = AnnotationEditorController(image: image, globalRect: globalRect, screen: screen) {
            [weak self] in self?.editor = nil
        }
        editor?.show()
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
