import AppKit

enum ImageSaver {
    /// 把 CGImage 存成 PNG 到桌面，返回路径
    static func saveToDesktop(cgImage: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Shot-\(formatter.string(from: Date())).png"

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent(name)
        do {
            try png.write(to: url)
            return url.path
        } catch {
            print("save error: \(error)")
            return nil
        }
    }
}
