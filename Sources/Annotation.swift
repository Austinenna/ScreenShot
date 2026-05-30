import AppKit

enum Tool {
    case line, arrow, box, text
}

/// 一条标注。坐标都用「屏幕局部点坐标」（左下原点）
enum Annotation {
    case line(from: NSPoint, to: NSPoint)
    case arrow(from: NSPoint, to: NSPoint)
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

        case let .arrow(from, to):
            Annotation.drawArrow(from: from, to: to)

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

    /// 画箭头：一根杆 + 实心三角箭头
    private static func drawArrow(from: NSPoint, to: NSPoint) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLen: CGFloat = 14 + lineWidth * 1.5
        let spread: CGFloat = .pi / 7   // 箭头张角

        let p1 = NSPoint(x: to.x - headLen * cos(angle - spread),
                         y: to.y - headLen * sin(angle - spread))
        let p2 = NSPoint(x: to.x - headLen * cos(angle + spread),
                         y: to.y - headLen * sin(angle + spread))

        // 杆：缩短到箭头根部，避免戳出三角尖
        let base = NSPoint(x: to.x - headLen * 0.8 * cos(angle),
                           y: to.y - headLen * 0.8 * sin(angle))
        let shaft = NSBezierPath()
        shaft.move(to: from)
        shaft.line(to: base)
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.stroke()

        // 三角箭头
        let head = NSBezierPath()
        head.move(to: to)
        head.line(to: p1)
        head.line(to: p2)
        head.close()
        head.fill()
    }
}
