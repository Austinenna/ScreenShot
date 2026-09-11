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

        // 监听 Esc / ⌘Z / 工具栏快捷键 1·2·3
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            // 正在输入文字时放行所有按键（让数字能正常输入）
            if self.annotationView?.isEditingText == true { return e }

            if e.keyCode == 53 { self.cancel(); return nil }                      // Esc
            if e.keyCode == 6 && e.modifierFlags.contains(.command) {             // ⌘Z
                self.annotationView?.undo(); return nil
            }
            // 工具栏快捷键（钉图 / 复制 / 保存），可在设置中自定义
            if self.matches(e, Settings.shared.pinKey)  { self.pinAction();  return nil }
            if self.matches(e, Settings.shared.copyKey) { self.copyAction(); return nil }
            if self.matches(e, Settings.shared.saveKey) { self.saveAction(); return nil }
            return e
        }
    }

    private var keyMonitor: Any?

    /// 事件是否匹配某个快捷键（键码 + 修饰键完全一致）
    private func matches(_ e: NSEvent, _ combo: HotKeyCombo) -> Bool {
        let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return e.keyCode == combo.keyCode
            && e.modifierFlags.intersection(mask) == combo.modifierFlags.intersection(mask)
    }

    // MARK: - 工具条

    private func buildToolbar() -> NSView {
        // (工具, SF符号, 名称, 动作, 快捷键)
        let items: [(Tool?, String, String, Selector, HotKeyCombo?)] = [
            (.line,  "line.diagonal",      "直线", #selector(selLine),  nil),
            (.arrow, "arrow.up.right",     "箭头", #selector(selArrow), nil),
            (.box,   "rectangle",          "方框", #selector(selBox),   nil),
            (.text,  "textformat",         "文字", #selector(selText),  nil),
            (nil,    "arrow.uturn.backward", "撤销", #selector(undo),   nil),
            (nil,    "pin",                "钉图", #selector(pinAction),  Settings.shared.pinKey),
            (nil,    "doc.on.doc",         "复制", #selector(copyAction), Settings.shared.copyKey),
            (nil,    "square.and.arrow.down", "保存", #selector(saveAction), Settings.shared.saveKey),
            (nil,    "xmark",              "取消", #selector(cancel),   nil),
        ]

        let btnW: CGFloat = 44, btnH: CGFloat = 36, pad: CGFloat = 6
        let width = CGFloat(items.count) * btnW + pad * 2
        let height = btnH + pad * 2

        // 可用屏幕区域转成编辑器局部坐标，避开菜单栏和 Dock，并留出边距。
        let margin: CGFloat = 10
        let visible = screen.visibleFrame.offsetBy(dx: -screen.frame.minX,
                                                  dy: -screen.frame.minY)
        let safeBounds = visible.insetBy(dx: margin, dy: margin)
        let belowY = localRect.minY - height - margin
        let aboveY = localRect.maxY + margin
        let maxY = safeBounds.maxY - height

        // 优先选区下方，其次上方；全屏等上下都放不下的选区，回落到屏幕内。
        var y = belowY
        if belowY < safeBounds.minY, aboveY <= maxY {
            y = aboveY
        }
        y = max(safeBounds.minY, min(y, maxY))
        let x = max(safeBounds.minX,
                    min(localRect.midX - width / 2, safeBounds.maxX - width))

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
            b.toolTip = item.4 == nil ? item.2 : "\(item.2) (\(item.4!.display))"
            b.target = self
            b.action = item.3
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            bar.addSubview(b)
            if let tool = item.0 { toolButtons[tool] = b }

            // 在按钮右下角标出快捷键
            if let key = item.4 {
                let badge = NSTextField(labelWithString: key.display)
                badge.font = .systemFont(ofSize: 9, weight: .semibold)
                badge.textColor = .secondaryLabelColor
                badge.alignment = .right
                badge.frame = NSRect(x: b.frame.maxX - 26, y: b.frame.minY + 1, width: 24, height: 11)
                bar.addSubview(badge)
            }
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
