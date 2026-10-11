import Cocoa

/// 框选完成后要执行的输出动作。
enum SelectionOutput: Equatable {
    case directCopy
    case annotation
}

/// 框选视图：冻结整屏画面 + 暗化选区外部 + 边框/把手 + 尺寸标签
final class SelectionView: NSView {
    var onFinish: ((CGRect?, SelectionOutput) -> Void)?

    private let snapshot: NSImage
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false
    private var output: SelectionOutput = .directCopy

    init(frame: NSRect, snapshot: CGImage) {
        self.snapshot = NSImage(cgImage: snapshot, size: frame.size)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // 用 tracking area 显式管理十字光标（borderless/后台窗口下比 cursorRects 可靠）
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent)   { NSCursor.crosshair.set() }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        beginSelection(with: event, output: .directCopy)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginSelection(with: event, output: .annotation)
    }

    private func beginSelection(with event: NSEvent, output: SelectionOutput) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        isDragging = true
        self.output = output
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updateSelection(with: event)
    }

    private func updateSelection(with event: NSEvent) {
        guard let start = startPoint else { return }
        let location = convert(event.locationInWindow, from: nil)
        let p = NSPoint(x: min(max(location.x, bounds.minX), bounds.maxX),
                        y: min(max(location.y, bounds.minY), bounds.maxY))
        currentRect = NSRect(x: min(start.x, p.x),
                             y: min(start.y, p.y),
                             width: abs(p.x - start.x),
                             height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        finishSelection()
    }

    override func rightMouseUp(with event: NSEvent) {
        finishSelection()
    }

    private func finishSelection() {
        isDragging = false
        if currentRect.width > 2 && currentRect.height > 2 {
            onFinish?(currentRect, output)
        } else {
            onFinish?(nil, output)  // 只是点了一下，取消
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish?(nil, output)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 始终显示同一张快照；选区内不挖透明洞，避免露出菜单已关闭的实时桌面。
        snapshot.draw(in: bounds)
        let shade = NSBezierPath(rect: bounds)
        if !currentRect.isEmpty { shade.appendRect(currentRect) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        shade.fill()

        guard currentRect.width > 0, currentRect.height > 0 else { return }

        // 选区边框
        let border = NSBezierPath(rect: currentRect)
        NSColor.systemBlue.setStroke()
        border.lineWidth = 1.5
        border.stroke()

        drawHandles()
        drawSizeLabel()
    }

    private func drawHandles() {
        let s: CGFloat = 6
        let pts = [
            NSPoint(x: currentRect.minX, y: currentRect.minY),
            NSPoint(x: currentRect.midX, y: currentRect.minY),
            NSPoint(x: currentRect.maxX, y: currentRect.minY),
            NSPoint(x: currentRect.minX, y: currentRect.midY),
            NSPoint(x: currentRect.maxX, y: currentRect.midY),
            NSPoint(x: currentRect.minX, y: currentRect.maxY),
            NSPoint(x: currentRect.midX, y: currentRect.maxY),
            NSPoint(x: currentRect.maxX, y: currentRect.maxY),
        ]
        NSColor.systemBlue.setFill()
        for p in pts {
            NSBezierPath(ovalIn: NSRect(x: p.x - s/2, y: p.y - s/2, width: s, height: s)).fill()
        }
    }

    private func drawSizeLabel() {
        let text = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 6
        var origin = NSPoint(x: currentRect.minX, y: currentRect.maxY + 6)
        if origin.y + size.height + pad * 2 > bounds.maxY {
            origin.y = currentRect.maxY - size.height - pad * 2 - 6
        }
        let bg = NSRect(x: origin.x, y: origin.y,
                        width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: origin.x + pad, y: origin.y + pad), withAttributes: attrs)
    }
}
