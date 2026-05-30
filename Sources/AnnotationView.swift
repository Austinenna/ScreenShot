import AppKit

/// 标注画布：暗化全屏 + 在选区里显示截图 + 在其上绘制标注
/// 坐标系：本视图覆盖整块屏幕，使用屏幕局部点坐标（左下原点）
final class AnnotationView: NSView {
    private let baseImage: NSImage
    private let selectionRect: NSRect      // 选区在本视图中的位置（点）
    private let scale: CGFloat             // backingScaleFactor，用于导出全分辨率

    var tool: Tool = .box

    private var annotations: [Annotation] = []
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var activeTextField: NSTextField?

    init(frame: NSRect, image: CGImage, selectionRect: NSRect, scale: CGFloat) {
        self.baseImage = NSImage(cgImage: image, size: selectionRect.size)
        self.selectionRect = selectionRect
        self.scale = scale
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(selectionRect, cursor: .crosshair)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        baseImage.draw(in: selectionRect)

        // 选区边框
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 1
        border.stroke()

        // 标注裁剪在选区内
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        for a in annotations { a.draw() }
        drawPreview()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawPreview() {
        guard let s = dragStart, let c = dragCurrent else { return }
        switch tool {
        case .line:
            Annotation.line(from: s, to: c).draw()
        case .arrow:
            Annotation.arrow(from: s, to: c).draw()
        case .box:
            Annotation.box(rect: rectBetween(s, c)).draw()
        case .text:
            break
        }
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        commitTextIfNeeded()
        let p = convert(event.locationInWindow, from: nil)
        guard selectionRect.contains(p) else { return }

        if tool == .text {
            beginTextEditing(at: p)
        } else {
            dragStart = p
            dragCurrent = p
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragCurrent = clamp(convert(event.locationInWindow, from: nil), to: selectionRect)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = dragStart, let c = dragCurrent else { return }
        dragStart = nil; dragCurrent = nil
        switch tool {
        case .line:
            if s.distance(to: c) > 2 { annotations.append(.line(from: s, to: c)) }
        case .arrow:
            if s.distance(to: c) > 2 { annotations.append(.arrow(from: s, to: c)) }
        case .box:
            let r = rectBetween(s, c)
            if r.width > 2 && r.height > 2 { annotations.append(.box(rect: r)) }
        case .text:
            break
        }
        needsDisplay = true
    }

    // MARK: - 文字

    private func beginTextEditing(at point: NSPoint) {
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 8, width: 160, height: 26))
        field.font = .systemFont(ofSize: Annotation.fontSize, weight: .semibold)
        field.textColor = Annotation.color
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "输入文字"
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitTextIfNeeded()
    }

    private func commitTextIfNeeded() {
        guard let field = activeTextField else { return }
        let text = field.stringValue
        let origin = NSPoint(x: field.frame.minX, y: field.frame.minY + 4)
        field.removeFromSuperview()
        activeTextField = nil
        if !text.isEmpty {
            annotations.append(.text(text, at: origin))
            needsDisplay = true
        }
    }

    // MARK: - 操作

    func undo() {
        commitTextIfNeeded()
        if !annotations.isEmpty {
            annotations.removeLast()
            needsDisplay = true
        }
    }

    /// 把截图 + 标注合成为全分辨率 CGImage
    func exportImage() -> CGImage? {
        commitTextIfNeeded()
        let pxW = Int((selectionRect.width * scale).rounded())
        let pxH = Int((selectionRect.height * scale).rounded())
        guard pxW > 0, pxH > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pxW, pixelsHigh: pxH,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = selectionRect.size  // 点尺寸 → 绘制用点坐标，像素自动按 scale 放大

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        // 把坐标系平移，使选区左下角对齐到 (0,0)
        let t = NSAffineTransform()
        t.translateX(by: -selectionRect.minX, yBy: -selectionRect.minY)
        t.concat()

        baseImage.draw(in: selectionRect)
        for a in annotations { a.draw() }

        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    // MARK: - 辅助

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func clamp(_ p: NSPoint, to r: NSRect) -> NSPoint {
        NSPoint(x: Swift.min(Swift.max(p.x, r.minX), r.maxX),
                y: Swift.min(Swift.max(p.y, r.minY), r.maxY))
    }
}

private extension NSPoint {
    func distance(to p: NSPoint) -> CGFloat { hypot(p.x - x, p.y - y) }
}
