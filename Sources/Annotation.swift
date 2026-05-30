import AppKit

enum Tool {
    case line, box, text
}

/// 一条标注。坐标都用「屏幕局部点坐标」（左下原点）
enum Annotation {
    case line(from: NSPoint, to: NSPoint)
    case box(rect: NSRect)
    case text(String, at: NSPoint)

    static let color = NSColor.systemRed
    static let lineWidth: CGFloat = 3
    static let fontSize: CGFloat = 18

    func draw() {
        Annotation.color.setStroke()
        Annotation.color.setFill()

        switch self {
        case let .line(from, to):
            let p = NSBezierPath()
            p.move(to: from)
            p.line(to: to)
            p.lineWidth = Annotation.lineWidth
            p.lineCapStyle = .round
            p.stroke()

        case let .box(rect):
            let p = NSBezierPath(rect: rect)
            p.lineWidth = Annotation.lineWidth
            p.stroke()

        case let .text(string, origin):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: Annotation.fontSize, weight: .semibold),
                .foregroundColor: Annotation.color,
            ]
            string.draw(at: origin, withAttributes: attrs)
        }
    }
}
