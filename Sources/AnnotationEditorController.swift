import AppKit

/// 标注编辑器：全屏覆盖窗 + 标注画布 + 浮动工具条（直线/方框/文字 + 复制/保存）
final class AnnotationEditorController {
    private let screen: NSScreen
    private let image: CGImage
    private let globalRect: CGRect         // 选区全局坐标（点）
    private let localRect: NSRect          // 选区在该屏幕的局部坐标（点）
    private let onClose: () -> Void
    private let onPin: (CGImage, CGRect) -> Void

    private var window: OverlayWindow?
    private var annotationView: AnnotationView?
    private var toolButtons: [Tool: NSButton] = [:]

    /// - globalRect: 选区全局坐标；image: 已截好的该区域图
    /// - onPin: 用户点「钉图」时回调（带合成图 + 全局位置），由上层创建钉图窗口
    init(image: CGImage, globalRect: CGRect, screen: NSScreen,
         onClose: @escaping () -> Void,
         onPin: @escaping (CGImage, CGRect) -> Void) {
        self.image = image
        self.screen = screen
        self.globalRect = globalRect
        self.onClose = onClose
        self.onPin = onPin
        self.localRect = NSRect(x: globalRect.minX - screen.frame.minX,
                                y: globalRect.minY - screen.frame.minY,
                                width: globalRect.width, height: globalRect.height)
    }

    func show() {
        let win = OverlayWindow(screen: screen)
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))

        let canvas = AnnotationView(frame: container.bounds, image: image,
                                    selectionRect: localRect, scale: screen.backingScaleFactor)
        canvas.tool = .box
        container.addSubview(canvas)
        annotationView = canvas

        container.addSubview(buildToolbar())
        win.contentView = container
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(canvas)
        updateToolHighlight()

        // 监听 Esc / ⌘Z
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.cancel(); return nil }                      // Esc
            if e.keyCode == 6 && e.modifierFlags.contains(.command) {             // ⌘Z
                self.annotationView?.undo(); return nil
            }
            return e
        }
    }

    private var keyMonitor: Any?

    // MARK: - 工具条

    private func buildToolbar() -> NSView {
        let items: [(Tool?, String, String, Selector)] = [
            (.line,  "line.diagonal",      "直线", #selector(selLine)),
            (.arrow, "arrow.up.right",     "箭头", #selector(selArrow)),
            (.box,   "rectangle",          "方框", #selector(selBox)),
            (.text,  "textformat",         "文字", #selector(selText)),
            (nil,    "arrow.uturn.backward", "撤销", #selector(undo)),
            (nil,    "pin",                "钉图", #selector(pinAction)),
            (nil,    "doc.on.doc",         "复制", #selector(copyAction)),
            (nil,    "square.and.arrow.down", "保存", #selector(saveAction)),
            (nil,    "xmark",              "取消", #selector(cancel)),
        ]

        let btnW: CGFloat = 44, btnH: CGFloat = 36, pad: CGFloat = 6
        let width = CGFloat(items.count) * btnW + pad * 2
        let height = btnH + pad * 2

        // 工具条放在选区下方；放不下就放上方
        var y = localRect.minY - height - 10
        if y < 10 { y = localRect.maxY + 10 }
        var x = localRect.midX - width / 2
        x = min(max(x, 10), screen.frame.width - width - 10)

        let bar = NSView(frame: NSRect(x: x, y: y, width: width, height: height))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bar.layer?.cornerRadius = 10
        bar.layer?.shadowColor = NSColor.black.cgColor
        bar.layer?.shadowOpacity = 0.25
        bar.layer?.shadowRadius = 8
        bar.layer?.shadowOffset = .zero

        for (i, item) in items.enumerated() {
            let b = NSButton(frame: NSRect(x: pad + CGFloat(i) * btnW, y: pad, width: btnW, height: btnH))
            b.bezelStyle = .regularSquare
            b.isBordered = false
            b.image = NSImage(systemSymbolName: item.1, accessibilityDescription: item.2)
            b.imageScaling = .scaleProportionallyDown
            b.toolTip = item.2
            b.target = self
            b.action = item.3
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            bar.addSubview(b)
            if let tool = item.0 { toolButtons[tool] = b }
        }
        return bar
    }

    private func updateToolHighlight() {
        let current = annotationView?.tool
        for (tool, btn) in toolButtons {
            btn.layer?.backgroundColor = (tool == current)
                ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
                : NSColor.clear.cgColor
        }
    }

    @objc private func selLine()  { annotationView?.tool = .line;  updateToolHighlight() }
    @objc private func selArrow() { annotationView?.tool = .arrow; updateToolHighlight() }
    @objc private func selBox()   { annotationView?.tool = .box;   updateToolHighlight() }
    @objc private func selText()  { annotationView?.tool = .text;  updateToolHighlight() }
    @objc private func undo()     { annotationView?.undo() }

    @objc private func pinAction() {
        guard let cg = annotationView?.exportImage() else { return }
        let scale = screen.backingScaleFactor
        let out = ImageDecorator.decorate(cg, scale: scale)
        let size = NSSize(width: CGFloat(out.width) / scale, height: CGFloat(out.height) / scale)
        // 钉图中心对齐原选区中心（加白边后尺寸会变大）
        let origin = NSPoint(x: globalRect.midX - size.width / 2,
                             y: globalRect.midY - size.height / 2)
        close()                      // 先收起编辑器
        onPin(out, CGRect(origin: origin, size: size))
    }

    // MARK: - 输出

    @objc private func copyAction() {
        guard let cg = annotationView?.exportImage() else { return }
        let scale = screen.backingScaleFactor
        let out = ImageDecorator.decorate(cg, scale: scale)
        let size = NSSize(width: CGFloat(out.width) / scale, height: CGFloat(out.height) / scale)
        let img = NSImage(cgImage: out, size: size)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        close()
    }

    @objc private func saveAction() {
        guard let raw = annotationView?.exportImage() else { return }
        let cg = ImageDecorator.decorate(raw, scale: screen.backingScaleFactor)

        // 直接保存到设置里的目录
        if ImageSaver.save(cgImage: cg, to: Settings.shared.saveDirectory) != nil {
            close()
            return
        }

        // 保存失败（目录不可写等）→ 回退到手动选择路径
        window?.orderOut(nil)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Shot.png"
        panel.begin { [weak self] resp in
            if resp == .OK, let url = panel.url {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            self?.close()
        }
    }

    @objc private func cancel() { close() }

    private func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        window?.orderOut(nil)
        window = nil
        onClose()
    }
}
