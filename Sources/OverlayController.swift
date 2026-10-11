import Cocoa

/// 在内存中的整屏快照上框选，完成或取消后释放快照。
final class OverlayController {
    private let screen: NSScreen
    private let completion: ((CGImage, CGRect, SelectionOutput)?) -> Void
    private var snapshot: CGImage?
    private var window: OverlayWindow?

    init(screen: NSScreen, snapshot: CGImage,
         completion: @escaping ((CGImage, CGRect, SelectionOutput)?) -> Void) {
        self.screen = screen
        self.snapshot = snapshot
        self.completion = completion
    }

    func show() {
        guard let snapshot else { return }
        let win = OverlayWindow(screen: screen)
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                 snapshot: snapshot)
        view.onFinish = { [weak self] localRect, output in
            self?.finish(localRect: localRect, output: output)
        }
        win.contentView = view
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
        NSCursor.crosshair.set()
    }

    /// localRect 是相对覆盖窗（= 该屏幕）的坐标，转换成全局屏幕坐标返回
    private func finish(localRect: CGRect?, output: SelectionOutput) {
        var result: (CGImage, CGRect, SelectionOutput)?
        if let r = localRect, let snapshot {
            let global = r.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            if let image = CaptureService.crop(snapshot, globalRect: global,
                                               screenFrame: screen.frame,
                                               scale: screen.backingScaleFactor) {
                result = (image, global, output)
            }
        }

        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        snapshot = nil
        completion(result)
    }
}

/// 无边框、置顶、可成为 key 的窗口
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        self.level = .screenSaver          // 盖在几乎所有东西之上
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
