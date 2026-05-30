import Cocoa

/// 管理覆盖在某块屏幕上的全屏透明窗口，用于框选
final class OverlayController {
    private let screen: NSScreen
    private let completion: (CGRect?) -> Void
    private var window: OverlayWindow?

    init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        self.screen = screen
        self.completion = completion
    }

    func show() {
        let win = OverlayWindow(screen: screen)
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] localRect in
            self?.finish(localRect: localRect)
        }
        win.contentView = view
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
        NSCursor.crosshair.set()
    }

    /// localRect 是相对覆盖窗（= 该屏幕）的坐标，转换成全局屏幕坐标返回
    private func finish(localRect: CGRect?) {
        window?.orderOut(nil)
        window = nil
        guard let r = localRect else {
            completion(nil)
            return
        }
        let global = CGRect(x: screen.frame.origin.x + r.origin.x,
                            y: screen.frame.origin.y + r.origin.y,
                            width: r.width,
                            height: r.height)
        completion(global)
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
