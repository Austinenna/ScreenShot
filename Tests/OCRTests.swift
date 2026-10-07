import AppKit

@main
struct OCRTests {
    @MainActor
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("OCR 测试失败：\(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        // 真实调用 Vision：测试图片由程序绘制，不使用用户屏幕或文件。
        for scale: CGFloat in [1, 2] {
            let image = fixture(lines: ["中文截图识别", "Hello Vision", "项目编号 A123"], scale: scale)
            let text = try await Task.detached { try OCRService.recognizeText(in: image) }.value
            let compact = text.replacingOccurrences(of: " ", with: "")
            try expect(compact.contains("中文截图识别"), "中文识别失败：\(text)")
            try expect(text.contains("Hello Vision"), "英文识别失败：\(text)")
            try expect(compact.contains("项目编号A123"), "中英文混排识别失败：\(text)")
            try expect(text.range(of: "中文")!.lowerBound < text.range(of: "Hello")!.lowerBound,
                         "识别顺序应从上到下")
            print("\(Int(scale))x 中英文识别通过：\(text.replacingOccurrences(of: "\n", with: " / "))")
        }

        let traditional = fixture(lines: ["繁體中文測試"], scale: 1)
        let traditionalText = try await Task.detached {
            try OCRService.recognizeText(in: traditional)
        }.value
        try expect(traditionalText.replacingOccurrences(of: " ", with: "").contains("繁體中文測試"),
                   "繁体中文识别失败：\(traditionalText)")
        print("繁体中文识别通过：\(traditionalText)")

        let blank = fixture(lines: [], scale: 1)
        let empty = try await Task.detached { try OCRService.recognizeText(in: blank) }.value
        try expect(empty.isEmpty, "空白图片不应产生文本")

        let ordered = OCRService.plainText(from: [
            .init(text: "下一行", bounds: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.1)),
            .init(text: "right", bounds: CGRect(x: 0.6, y: 0.71, width: 0.2, height: 0.1)),
            .init(text: "left", bounds: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1))
        ])
        try expect(ordered == "left right\n下一行", "文本片段排列错误")

        // 专用剪贴板验证写入和空结果保护，保持用户系统剪贴板不变。
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("保留原内容", forType: .string)
        try expect(!OCRService.copyText(empty, to: pasteboard), "空结果不应写入")
        try expect(!OCRService.copyText(" \n ", to: pasteboard), "纯空白不应写入")
        try expect(pasteboard.string(forType: .string) == "保留原内容", "空结果改变了原剪贴板")
        try expect(OCRService.copyText(ordered, to: pasteboard), "文字复制失败")
        try expect(pasteboard.string(forType: .string) == ordered, "复制后的文字发生变化")
        // AppKit 可能同时声明多种文本编码，不能要求 types 只有一个条目。
        try expect(pasteboard.data(forType: .png) == nil && pasteboard.data(forType: .tiff) == nil,
                   "识别结果不应包含图片")
        print("通过：原生 Vision 中英文/混排/1x/2x/空白图、文本顺序和剪贴板写入/空结果保护")
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    @MainActor
    private static func fixture(lines: [String], scale: CGFloat) -> CGImage {
        let size = CGSize(width: 640, height: 260)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                  pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        CGRect(origin: .zero, size: size).fill()
        for (index, line) in lines.enumerated() {
            line.draw(at: CGPoint(x: 30, y: 190 - index * 65), withAttributes: [
                .font: NSFont.systemFont(ofSize: 36),
                .foregroundColor: NSColor.black
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
