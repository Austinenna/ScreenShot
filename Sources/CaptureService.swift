import ScreenCaptureKit
import AppKit

/// 先捕获整屏快照，再从内存快照中裁剪选区。
enum CaptureService {

    /// 必须在激活截图应用或显示框选窗口之前调用；快照不写入磁盘。
    @available(macOS 14.0, *)
    @MainActor
    static func capture(screen: NSScreen) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)

            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value

            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
                    else { return nil }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            // 关键：整屏按「全像素」分辨率截取，不用 sourceRect 让它帮我们缩放裁剪
            config.width  = Int(screen.frame.width  * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } catch {
            print("capture error: \(error)")
            return nil
        }
    }

    /// 像素级裁剪并复制选区，避免裁剪图继续共享整屏图的底层存储。
    static func crop(_ full: CGImage,
                     globalRect: CGRect,
                     screenFrame: CGRect,
                     scale: CGFloat) -> CGImage? {
        guard scale > 0, globalRect.width > 2, globalRect.height > 2 else { return nil }
        // 全局坐标 → 该屏幕局部坐标（左下原点）
        let localX = globalRect.origin.x - screenFrame.origin.x
        let localYBottom = globalRect.origin.y - screenFrame.origin.y
        // CGImage 原点在左上，需翻转 Y
        let localYTop = screenFrame.height - (localYBottom + globalRect.height)

        // 点 → 像素
        let pixelRect = CGRect(x: (localX * scale).rounded(),
                               y: (localYTop * scale).rounded(),
                               width: (globalRect.width * scale).rounded(),
                               height: (globalRect.height * scale).rounded())
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))

        guard !pixelRect.isNull, !pixelRect.isEmpty,
              let cropped = full.cropping(to: pixelRect),
              let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: full.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return context.makeImage()
    }
}
