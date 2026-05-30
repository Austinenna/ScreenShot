import Cocoa

/// 框选视图：暗化全屏 + 镂空选区 + 边框/把手 + 尺寸标签
final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false

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
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(start.x, p.x),
                             y: min(start.y, p.y),
                             width: abs(p.x - start.x),
                             height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if currentRect.width > 2 && currentRect.height > 2 {
            onFinish?(currentRect)
        } else {
            onFinish?(nil)  // 只是点了一下，取消
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish?(nil)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 整屏暗化
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard currentRect.width > 0, currentRect.height > 0 else { return }

        // 镂空选区（恢复清晰）
        NSColor.clear.setFill()
        currentRect.fill(using: .copy)

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
