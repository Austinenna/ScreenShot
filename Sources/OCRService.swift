import AppKit
import Vision

/// 使用系统 Vision 在本机识别截图中的中英文，不上传或保存图片。
enum OCRService {
    /// 串行化 Vision 请求，避免启动预热与用户第一次识别同时加载模型。
    private static let requestQueue = DispatchQueue(label: "com.prototype.screenshot.ocr")
    private static var didPrewarm = false

    /// 在后台预先加载 Vision OCR 模型，避免第一次用户识别承担冷启动延迟。
    static func prewarm() {
        requestQueue.async {
            guard !didPrewarm else { return }
            do {
                let request = try makeRequest()
                let handler = VNImageRequestHandler(cgImage: warmupImage(),
                                                     orientation: .up, options: [:])
                try handler.perform([request])
                didPrewarm = true
            } catch {
                // 预热失败不影响真正识别；下一次识别仍会按需初始化。
                print("OCR prewarm error: \(error)")
            }
        }
    }

    /// 同步识别，应在后台任务中调用。
    static func recognizeText(in image: CGImage) throws -> String {
        try requestQueue.sync {
            try Task.checkCancellation()
            let request = try makeRequest()
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            try handler.perform([request])
            try Task.checkCancellation()
            let lines = (request.results ?? []).compactMap { observation -> Line? in
                guard let text = observation.topCandidates(1).first?.string
                    .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return Line(text: text, bounds: observation.boundingBox)
            }
            return plainText(from: lines)
        }
    }

    struct Line {
        let text: String
        let bounds: CGRect
    }

    /// 普通横排文本按行从上到下，同一行的片段从左到右。不还原表格或多栏布局。
    static func plainText(from lines: [Line]) -> String {
        let sorted = lines.sorted {
            if $0.bounds.midY == $1.bounds.midY { return $0.bounds.minX < $1.bounds.minX }
            return $0.bounds.midY > $1.bounds.midY
        }
        var rows: [[Line]] = []
        for line in sorted {
            if let anchor = rows.last?.first,
               abs(anchor.bounds.midY - line.bounds.midY) <= min(anchor.bounds.height, line.bounds.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            row.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// 没有识别结果时保留原剪贴板。可传入专用剪贴板进行验证。
    @MainActor
    static func copyText(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private enum RecognitionError: Error {
        case unsupportedLanguages
    }

    private static func makeRequest() throws -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter(supported.contains)
        guard !request.recognitionLanguages.isEmpty else { throw RecognitionError.unsupportedLanguages }
        return request
    }

    private static func warmupImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 8, height: 8,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }
}
