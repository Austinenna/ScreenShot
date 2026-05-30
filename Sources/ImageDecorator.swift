import AppKit

/// 输出前的装饰处理：根据设置给截图加白色圆角边框
enum ImageDecorator {
    // 截图自身圆角（点）；外圆角 = 内圆角 + 白边宽度，保证白框处处等宽
    private static let innerRadius: CGFloat = 8

    /// 若开关关闭，原样返回；否则返回带白色圆角边框的新图（外圆角外为透明）
    static func decorate(_ image: CGImage, scale: CGFloat) -> CGImage {
        guard Settings.shared.whiteBorder else { return image }

        let padding = Settings.shared.borderWidth
        let pad = Int((padding * scale).rounded())
        let innerR = innerRadius * scale
        let outerR = innerR + padding * scale
        let w = image.width + pad * 2
        let h = image.height + pad * 2

        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high

        // 整块画布画成白色圆角矩形（四角之外保持透明）
        let outer = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: outerR, cornerHeight: outerR, transform: nil))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillPath()

        // 截图裁成稍小的圆角矩形后绘入
        let inner = CGRect(x: pad, y: pad, width: image.width, height: image.height)
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: innerR, cornerHeight: innerR, transform: nil))
        ctx.clip()
        ctx.draw(image, in: inner)

        return ctx.makeImage() ?? image
    }
}
