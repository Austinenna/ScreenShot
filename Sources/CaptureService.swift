import ScreenCaptureKit
import AppKit

/// 提供整屏、指定内容和内存快照裁剪三类截图能力。
enum CaptureService {

    /// 按内容过滤器截取指定内容（例如系统窗口选择器返回的窗口）。
    /// 输出保持内容过滤器提供的像素比例，避免窗口截图在 Retina 屏上发虚。
    @available(macOS 14.0, *)
    static func capture(contentFilter: SCContentFilter, scale: CGFloat) async -> CGImage? {
        guard scale > 0 else { return nil }
        do {
            let width = max(Int((contentFilter.contentRect.width * scale).rounded()), 1)
            let height = max(Int((contentFilter.contentRect.height * scale).rounded()), 1)
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.showsCursor = false
            config.captureResolution = .best

            return try await SCScreenshotManager.captureImage(
                contentFilter: contentFilter, configuration: config)
        } catch {
            print("capture content error: \(error)")
            return nil
        }
    }

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
