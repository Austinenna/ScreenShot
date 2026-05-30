import ScreenCaptureKit
import AppKit

/// 用 ScreenCaptureKit 截取指定屏幕区域（macOS 14+）
@available(macOS 14.0, *)
enum CaptureService {

    /// - globalRect: 全局屏幕坐标（左下角为原点，单位：点）
    /// - screen: 该区域所在的屏幕
    static func capture(globalRect: CGRect, screen: NSScreen) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)

            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value

            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
                    ?? content.displays.first else { return nil }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            // 关键：整屏按「全像素」分辨率截取，不用 sourceRect 让它帮我们缩放裁剪
            config.width  = Int(screen.frame.width  * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best

            let full = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)

            return crop(full, globalRect: globalRect, screen: screen, scale: scale)
        } catch {
            print("capture error: \(error)")
            return nil
        }
    }

    /// 在全屏像素图上做像素级裁剪（无重采样，保持原画质）
    private static func crop(_ full: CGImage,
                             globalRect: CGRect,
                             screen: NSScreen,
                             scale: CGFloat) -> CGImage? {
        // 全局坐标 → 该屏幕局部坐标（左下原点）
        let localX = globalRect.origin.x - screen.frame.origin.x
        let localYBottom = globalRect.origin.y - screen.frame.origin.y
        // CGImage 原点在左上，需翻转 Y
        let localYTop = screen.frame.height - (localYBottom + globalRect.height)

        // 点 → 像素
        let pixelRect = CGRect(x: (localX * scale).rounded(),
                               y: (localYTop * scale).rounded(),
                               width: (globalRect.width * scale).rounded(),
                               height: (globalRect.height * scale).rounded())
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))

        return full.cropping(to: pixelRect)
    }
}
