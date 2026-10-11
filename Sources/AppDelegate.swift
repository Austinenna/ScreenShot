import Cocoa
import ScreenCaptureKit

enum CaptureMode {
    case quick   // 截图后直接复制
    case normal  // 截图后进入标注
    case ocr     // 截图后识别文字并复制
}

final class AppDelegate: NSObject, NSApplicationDelegate, SCContentSharingPickerObserver {
    private var statusItem: NSStatusItem!
    private var overlay: OverlayController?
    private var editor: AnnotationEditorController?
    private var settingsWC: SettingsWindowController?
    private var pins: [PinController] = []   // 持有钉图窗口，防止被释放
    private var pinCacheIDs: [ObjectIdentifier: String] = [:]
    private var historyWC: HistoryWindowController?
    private let screenshotCache = ScreenshotCache.shared
    private var cacheCleanupTimer: Timer?
    private var isCapturing = false         // 整屏取图期间也阻止重复触发
    private var ocrTask: Task<String, Error>?
    private var notifyReset: DispatchWorkItem?
    private var windowPicker: SCContentSharingPicker?

    private var quickHotKeyID: UInt32?
    private var normalHotKeyID: UInt32?
    private var fullScreenHotKeyID: UInt32?
    private var windowCaptureHotKeyID: UInt32?
    private var ocrHotKeyID: UInt32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotKeys()
        OCRService.prewarm()
        purgeExpiredCache()
        cacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60,
                                                  repeats: true) { [weak self] _ in
            self?.purgeExpiredCache()
        }
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
        let f = Settings.shared.fullScreen.display
        let w = Settings.shared.windowCapture.display
        let o = Settings.shared.ocr.display
        menu.addItem(withTitle: "快捷截图（直接复制）  \(q)", action: #selector(quickCapture), keyEquivalent: "")
        menu.addItem(withTitle: "标注截图  \(n)", action: #selector(normalCapture), keyEquivalent: "")
        menu.addItem(withTitle: "截全屏（直接复制）  \(f)", action: #selector(fullScreenCapture), keyEquivalent: "")
        menu.addItem(withTitle: "截我选中的窗口（直接复制）  \(w)", action: #selector(windowCapture), keyEquivalent: "")
        menu.addItem(withTitle: "最近截图…", action: #selector(openHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "文字识别（直接复制）  \(o)", action: #selector(ocrCapture), keyEquivalent: "")
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
        if let id = fullScreenHotKeyID { HotKeyManager.shared.unregister(id) }
        if let id = windowCaptureHotKeyID { HotKeyManager.shared.unregister(id) }
        if let id = ocrHotKeyID { HotKeyManager.shared.unregister(id) }

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
        let fullScreen = Settings.shared.fullScreen
        fullScreenHotKeyID = HotKeyManager.shared.register(
            keyCode: fullScreen.keyCode, modifiers: fullScreen.carbonModifiers) { [weak self] in
                self?.fullScreenCapture()
        }
        let windowCapture = Settings.shared.windowCapture
        windowCaptureHotKeyID = HotKeyManager.shared.register(
            keyCode: windowCapture.keyCode, modifiers: windowCapture.carbonModifiers) { [weak self] in
                self?.windowCapture()
        }
        let ocr = Settings.shared.ocr
        ocrHotKeyID = HotKeyManager.shared.register(
            keyCode: ocr.keyCode, modifiers: ocr.carbonModifiers) { [weak self] in
                self?.startCapture(mode: .ocr)
        }
        rebuildMenu()
    }

    // MARK: - 截图流程

    @objc private func quickCapture()  { startCapture(mode: .quick) }
    @objc private func normalCapture() { startCapture(mode: .normal) }
    @objc private func ocrCapture()    { startCapture(mode: .ocr) }

    /// 截取鼠标所在屏幕的完整画面并直接复制。
    @objc private func fullScreenCapture() {
        guard !isCapturing, overlay == nil, editor == nil, ocrTask == nil else { return }
        guard #available(macOS 14.0, *) else { print("需要 macOS 14+"); return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        guard let target = screenCaptureTarget(for: screen) else {
            notify(text: "找不到当前显示器")
            return
        }

        isCapturing = true
        let captureTask = Task.detached(priority: .userInitiated) {
            await CaptureService.capture(displayID: target.displayID,
                                         pixelWidth: target.pixelWidth,
                                         pixelHeight: target.pixelHeight)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCapturing = false }
            guard let image = await captureTask.value else {
                self.notify(text: "截图失败，请检查屏幕录制权限")
                return
            }
            self.deliverQuick(image: image, scale: screen.backingScaleFactor, source: "全屏截图")
        }
    }

    /// 打开 macOS 系统窗口选择器，选定后只截取该窗口并直接复制。
    @objc private func windowCapture() {
        guard !isCapturing, overlay == nil, editor == nil, ocrTask == nil else { return }
        guard #available(macOS 14.0, *) else { print("需要 macOS 14+"); return }

        isCapturing = true
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.allowsChangingSelectedContent = false
        if let bundleID = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleID]
        }
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
        picker.add(self)
        picker.isActive = true
        windowPicker = picker
        picker.present(using: .window)
    }

    // MARK: - 系统窗口选择器

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopWindowPicker()
            self.isCapturing = false
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter,
                              for stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing, self.windowPicker != nil else { return }
            self.stopWindowPicker()
            let scale = max(CGFloat(filter.pointPixelScale), 1)
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.isCapturing = false }
                guard let image = await CaptureService.capture(contentFilter: filter, scale: scale) else {
                    self.notify(text: "窗口截图失败，请重试")
                    return
                }
                self.deliverQuick(image: image, scale: scale, source: "窗口截图")
            }
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopWindowPicker()
            self.isCapturing = false
            self.notify(text: "无法打开窗口选择器，请重试")
            print("window picker error: \(error)")
        }
    }

    private func stopWindowPicker() {
        guard let picker = windowPicker else { return }
        picker.remove(self)
        picker.isActive = false
        picker.maximumStreamCount = nil
        windowPicker = nil
    }

    private func screenCaptureTarget(for screen: NSScreen)
        -> (displayID: CGDirectDisplayID, pixelWidth: Int, pixelHeight: Int)? {
        guard let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
        let scale = screen.backingScaleFactor
        return (displayID,
                Int((screen.frame.width * scale).rounded()),
                Int((screen.frame.height * scale).rounded()))
    }

    private func startCapture(mode: CaptureMode) {
        guard !isCapturing, overlay == nil, editor == nil, ocrTask == nil else { return }
        guard #available(macOS 14.0, *) else { print("需要 macOS 14+"); return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        guard let target = screenCaptureTarget(for: screen) else {
            notify(text: "找不到当前显示器")
            return
        }

        // 在激活应用、显示遮罩之前取图，保留其他应用当前打开的菜单。
        isCapturing = true
        let captureTask = Task.detached(priority: .userInitiated) {
            await CaptureService.capture(displayID: target.displayID,
                                         pixelWidth: target.pixelWidth,
                                         pixelHeight: target.pixelHeight)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let snapshot = await captureTask.value else {
                self.isCapturing = false
                self.notify(text: "截图失败，请检查屏幕录制权限")
                return
            }

            self.overlay = OverlayController(screen: screen, snapshot: snapshot) { [weak self] result in
                guard let self else { return }
                self.overlay = nil
                self.isCapturing = false
                guard let (image, rect) = result else { return }
                switch mode {
                case .quick:  self.deliverQuick(image: image, scale: screen.backingScaleFactor, source: "区域截图")
                case .normal: self.openEditor(image: image, globalRect: rect, screen: screen)
                case .ocr:    self.recognizeAndCopy(image: image)
                }
            }
            self.overlay?.show()
        }
    }

    // OCR 模式：直接识别未添加标注和白边的选区，完成后复制纯文本。
    @MainActor
    private func recognizeAndCopy(image: CGImage) {
        notify(text: "正在识别文字…", clearsAfter: nil)
        let task = Task.detached(priority: .userInitiated) {
            try OCRService.recognizeText(in: image)
        }
        ocrTask = task
        Task { @MainActor [weak self] in
            guard let self else { task.cancel(); return }
            defer { self.ocrTask = nil }
            do {
                let text = try await task.value
                if text.isEmpty {
                    self.notify(text: "未识别到文字")
                } else if OCRService.copyText(text) {
                    self.notify(text: "已复制文字")
                } else {
                    self.notify(text: "复制文字失败，请重试")
                }
            } catch {
                self.notify(text: "文字识别失败，请重试")
                print("OCR error: \(error)")
            }
        }
    }

    // 快捷模式：直接复制
    @MainActor
    private func deliverQuick(image: CGImage, scale: CGFloat, source: String) {
        let out = ImageDecorator.decorate(image, scale: scale)
        let pointSize = NSSize(width: CGFloat(out.width) / scale, height: CGFloat(out.height) / scale)
        let nsImage = NSImage(cgImage: out, size: pointSize)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        notify(text: "已复制到剪贴板")
        cacheImage(out, source: source)
    }

    // 正常模式：进入标注编辑器
    @MainActor
    private func openEditor(image: CGImage, globalRect: CGRect, screen: NSScreen) {
        editor = AnnotationEditorController(
            image: image, globalRect: globalRect, screen: screen,
            onClose: { [weak self] in self?.editor = nil },
            onPin: { [weak self] cg, rect in
                self?.cacheAndPin(image: cg, globalRect: rect, source: "标注截图")
            },
            onCache: { [weak self] image in
                self?.cacheImage(image, source: "标注截图")
            })
        editor?.show()
    }

    // 创建一个钉图窗口并持有
    @MainActor
    private func pin(image: CGImage, globalRect: CGRect, cacheID: String? = nil) {
        let pin = PinController(image: image, globalRect: globalRect) { [weak self] controller in
            guard let self else { return }
            self.pins.removeAll { $0 === controller }
            self.pinCacheIDs.removeValue(forKey: ObjectIdentifier(controller))
        }
        pins.append(pin)
        if let cacheID {
            pinCacheIDs[ObjectIdentifier(pin)] = cacheID
        }
        pin.show()
    }

    /// 把最终输出的图片写入文件缓存。复制动作本身不等待磁盘写入，避免影响截图响应。
    @MainActor
    private func cacheImage(_ image: CGImage, source: String) {
        let width = image.width
        let height = image.height
        let cache = screenshotCache
        Task.detached(priority: .utility) { [weak self] in
            do {
                let representation = NSBitmapImageRep(cgImage: image)
                guard let png = representation.representation(using: .png, properties: [:]) else {
                    throw ScreenshotCacheError.invalidImageData
                }
                _ = try await cache.add(pngData: png, source: source,
                                        width: width, height: height)
                await MainActor.run { [weak self] in self?.historyWC?.refresh() }
            } catch {
                await MainActor.run { [weak self] in
                    self?.notify(text: "截图未加入历史")
                }
                print("screenshot cache error: \(error)")
            }
        }
    }

    /// 历史面板里的钉图需要先登记缓存，再把记录 ID 绑定到 PinController。
    @MainActor
    private func cacheAndPin(image: CGImage, globalRect: CGRect, source: String) {
        let width = image.width
        let height = image.height
        let cache = screenshotCache
        Task.detached(priority: .utility) { [weak self] in
            do {
                let representation = NSBitmapImageRep(cgImage: image)
                guard let png = representation.representation(using: .png, properties: [:]) else {
                    throw ScreenshotCacheError.invalidImageData
                }
                let record = try await cache.add(pngData: png, source: source,
                                                 width: width, height: height)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.pin(image: image, globalRect: globalRect, cacheID: record.id)
                    self.historyWC?.refresh()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.pin(image: image, globalRect: globalRect)
                    self.notify(text: "已钉图，但未加入截图历史")
                }
                print("screenshot cache pin error: \(error)")
            }
        }
    }

    private func purgeExpiredCache() {
        let cache = screenshotCache
        Task { [weak self] in
            guard let self else { return }
            do {
                let removed = try await cache.purgeExpired()
                guard !removed.isEmpty else { return }
                let ids = Set(removed.map(\.id))
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let expiredPins = self.pins.filter { pin in
                        guard let id = self.pinCacheIDs[ObjectIdentifier(pin)] else { return false }
                        return ids.contains(id)
                    }
                    expiredPins.forEach { $0.closeFromCacheExpiry() }
                    self.historyWC?.refresh()
                    self.notify(text: "截图已过期，已从历史和钉图移除")
                }
            } catch {
                print("screenshot cache purge error: \(error)")
            }
        }
    }

    @MainActor @objc private func openHistory() {
        if historyWC == nil {
            let dataSource = ScreenshotCacheHistoryDataSource(cache: screenshotCache)
            historyWC = HistoryWindowController(
                dataSource: dataSource,
                onCopy: { [weak self] _, image in
                    guard let self else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    self.notify(text: "已重新复制截图")
                },
                onPin: { [weak self] item, image in
                    self?.pinHistoryItem(item, image: image)
                })
        }
        historyWC?.showAndFocus()
    }

    @MainActor
    private func pinHistoryItem(_ item: ScreenshotHistoryItem, image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            notify(text: "读取截图失败")
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let aspect = CGFloat(cg.height) / max(CGFloat(cg.width), 1)
        var width = min(max(image.size.width, 120), visible.width * 0.72)
        var height = width * aspect
        if height > visible.height * 0.72 {
            height = visible.height * 0.72
            width = height / max(aspect, 0.01)
        }
        let origin = CGPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        pin(image: cg, globalRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
            cacheID: item.id)
        notify(text: "已钉图 · 24 小时后自动关闭")
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

    private func notify(text: String, clearsAfter delay: TimeInterval? = 1.5) {
        notifyReset?.cancel()
        notifyReset = nil
        statusItem.button?.title = " " + text
        guard let delay else { return }
        let reset = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.title = ""
        }
        notifyReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: reset)
    }

    @objc private func quit() {
        ocrTask?.cancel()
        NSApp.terminate(nil)
    }
}
