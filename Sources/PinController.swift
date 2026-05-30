import AppKit

/// 把一张图「钉」在屏幕上：浮动置顶、可拖动、双击关闭、滚轮缩放
final class PinController {
    private var window: PinWindow?
    private let onClose: (PinController) -> Void

    /// - image: 要钉的图（已合成的全分辨率位图）
    /// - globalRect: 初始出现的位置/尺寸（全局点坐标），通常就是截图选区
    init(image: CGImage, globalRect: CGRect, onClose: @escaping (PinController) -> Void) {
        self.onClose = onClose
        let win = PinWindow(image: image, frame: globalRect)
        win.onRequestClose = { [weak self] in self?.close() }
        self.window = win
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        onClose(self)
    }
}

/// 钉图窗口本体
final class PinWindow: NSWindow {
    var onRequestClose: (() -> Void)?
    private let pinView: PinView

    init(image: CGImage, frame: CGRect) {
        pinView = PinView(image: image, frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        level = .floating          // 浮在普通窗口之上
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false  // 自己处理拖动
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        pinView.onRequestClose = { [weak self] in self?.onRequestClose?() }
        contentView = pinView
    }

    override var canBecomeKey: Bool { true }
}

/// 钉图内容视图：画图 + 拖动 + 双击关闭 + 滚轮缩放
private final class PinView: NSView {
    var onRequestClose: (() -> Void)?
    private let image: NSImage
    private let aspect: CGFloat
    private var dragOrigin: NSPoint?      // 鼠标按下时的屏幕坐标
    private var winOrigin: NSPoint?       // 按下时窗口原点

    init(image cg: CGImage, frame: NSRect) {
        self.image = NSImage(cgImage: cg, size: frame.size)
        self.aspect = frame.height / max(frame.width, 1)
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        // 细边框，便于在浅色背景上分辨钉图边界
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.stroke()
    }

    // 双击关闭，单击开始拖动
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onRequestClose?()
            return
        }
        dragOrigin = NSEvent.mouseLocation
        winOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin, let origin = winOrigin else { return }
        let now = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: origin.x + (now.x - start.x),
                                       y: origin.y + (now.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil; winOrigin = nil
    }

    // 滚轮缩放（以中心为锚点），保持宽高比
    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let factor = 1 + event.scrollingDeltaY * 0.003
        let f = window.frame
        var newW = f.width * factor
        newW = min(max(newW, 60), 4000)
        let newH = newW * aspect
        let newX = f.midX - newW / 2
        let newY = f.midY - newH / 2
        window.setFrame(NSRect(x: newX, y: newY, width: newW, height: newH), display: true)
    }

    // 右键菜单提供关闭
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "关闭钉图", action: #selector(closeFromMenu), keyEquivalent: "")
        m.items.last?.target = self
        return m
    }

    @objc private func closeFromMenu() { onRequestClose?() }
}
