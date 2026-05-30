import AppKit

/// 一个可点击录制快捷键的控件：点一下进入录制态，按下组合键即记录
final class HotKeyRecorderView: NSView {
    var combo: HotKeyCombo {
        didSet { needsDisplay = true }
    }
    var onChange: ((HotKeyCombo) -> Void)?

    /// 是否强制要求修饰键（全局快捷键 true；工具栏单键 false）
    var requiresModifier = true

    private var recording = false {
        didSet { needsDisplay = true }
    }

    init(combo: HotKeyCombo) {
        self.combo = combo
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        if event.keyCode == 53 { // Esc 取消录制
            recording = false
            window?.makeFirstResponder(nil)
            return
        }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // 全局快捷键至少需要一个修饰键，避免和普通输入冲突
        if requiresModifier && mods.isEmpty {
            NSSound.beep()
            return
        }

        combo = HotKeyCombo(keyCode: event.keyCode, modifierFlags: mods)
        onChange?(combo)
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = recording ? .controlAccentColor.withAlphaComponent(0.15) : .controlBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        path.fill()
        layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor

        let text = recording ? "按下快捷键…" : combo.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2),
                  withAttributes: attrs)
    }
}
