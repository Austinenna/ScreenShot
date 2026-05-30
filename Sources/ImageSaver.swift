import AppKit

enum ImageSaver {
    /// 把 CGImage 存成 PNG 到指定目录，返回完整路径；失败返回 nil
    static func save(cgImage: CGImage, to directory: URL) -> String? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }

        // 确保目录存在
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("Shot-\(formatter.string(from: Date())).png")
        do {
            try png.write(to: url)
            return url.path
        } catch {
            print("save error: \(error)")
            return nil
        }
    }
}
