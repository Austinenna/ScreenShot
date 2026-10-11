import AppKit

/// 使用合成画面验证快照裁剪和绘制，不截取用户屏幕、不修改剪贴板。
@main
struct CaptureSnapshotTests {
    @MainActor
    static func main() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = 240, height = 160
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // 每个像素都有坐标特征，能发现翻转、偏移和缩放错误。
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                data[offset] = UInt8(x)
                data[offset + 1] = UInt8(y)
                data[offset + 2] = 100
                data[offset + 3] = 255
            }
        }
        let snapshot = context.makeImage()!
        var checks = 0
        for scale: CGFloat in [1, 2] {
            let size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
            for origin in [CGPoint.zero, CGPoint(x: -1920, y: 200), CGPoint(x: 120, y: -1080)] {
                let screen = CGRect(origin: origin, size: size)
                let selections = [
                    CGRect(origin: .zero, size: size),
                    CGRect(x: 10, y: 15, width: 30, height: 20),
                    CGRect(x: 0, y: 0, width: 30, height: 20),
                    CGRect(x: size.width - 30, y: size.height - 20, width: 30, height: 20)
                ]
                for local in selections {
                    let crop = CaptureService.crop(snapshot,
                                                   globalRect: local.offsetBy(dx: origin.x, dy: origin.y),
                                                   screenFrame: screen, scale: scale)!
                    let expectedWidth = Int(local.width * scale)
                    let expectedHeight = Int(local.height * scale)
                    precondition(crop.width == expectedWidth && crop.height == expectedHeight)
                    let pixels = rgba(crop)
                    let sourceX = Int(local.minX * scale)
                    let sourceY = height - Int(local.maxY * scale)
                    for y in 0..<expectedHeight {
                        for x in 0..<expectedWidth {
                            let offset = (y * expectedWidth + x) * 4
                            precondition(pixels[offset] == UInt8(sourceX + x), "裁剪横坐标错误")
                            precondition(pixels[offset + 1] == UInt8(sourceY + y), "裁剪纵坐标错误")
                            precondition(pixels[offset + 2] == 100 && pixels[offset + 3] == 255)
                        }
                    }
                    if crop.width < width && crop.height < height {
                        let storedBytes = CFDataGetLength(crop.dataProvider!.data!)
                        precondition(storedBytes < width * height * 4, "小图仍使用整屏大小的存储")
                    }
                    checks += 1
                }
            }
        }

        let screen = CGRect(x: 0, y: 0, width: width, height: height)
        precondition(CaptureService.crop(snapshot, globalRect: .zero, screenFrame: screen, scale: 1) == nil)
        precondition(CaptureService.crop(snapshot, globalRect: CGRect(x: 500, y: 500, width: 20, height: 20),
                                         screenFrame: screen, scale: 1) == nil)
        precondition(CaptureService.crop(snapshot, globalRect: screen, screenFrame: screen, scale: 0) == nil)

        // 保留小图时，原始整屏图的数据提供者也必须能释放。
        let probe = ReleaseProbe()
        let detached = detachedCrop(probe: probe)
        precondition(probe.released, "裁剪结果仍持有整屏图数据")
        precondition(detached.width == 20 && detached.height == 20)

        // 模拟菜单快照：整张白图。框选后内部必须仍不透明、保持原图，外部才暗化。
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(screen)
        let white = context.makeImage()!
        let view = SelectionView(frame: screen, snapshot: white)
        let selection = CGRect(x: 40, y: 40, width: 120, height: 80)
        view.mouseDown(with: mouse(.leftMouseDown, at: selection.origin))
        view.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: selection.maxX, y: selection.maxY)))
        let rendered = render(view)
        let pixels = rgba(rendered)
        let inside = (80 * width + 100) * 4
        let outside = (80 * width + 10) * 4
        precondition(pixels[inside] > 245 && pixels[inside + 3] == 255, "选区必须显示不透明的冻结画面")
        precondition((150...180).contains(Int(pixels[outside])) && pixels[outside + 3] == 255,
                     "选区外应该显示暗化的冻结画面")

        var completed: (CGRect, SelectionOutput)?
        view.onFinish = { rect, output in
            completed = rect.map { ($0, output) }
        }
        view.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: selection.maxX, y: selection.maxY)))
        precondition(completed?.0 == selection && completed?.1 == .directCopy)
        // Esc 取消；单击也应取消。
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                     isARepeat: false, keyCode: 53)!
        view.keyDown(with: escape)
        precondition(completed == nil)
        view.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        view.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 20, y: 20)))
        precondition(completed == nil)

        // 右键拖拽同样完成选区，但输出动作应切换为标注。
        let annotatedSelection = CGRect(x: 60, y: 30, width: 80, height: 50)
        view.rightMouseDown(with: mouse(.rightMouseDown, at: annotatedSelection.origin))
        view.rightMouseDragged(with: mouse(.rightMouseDragged,
                                            at: CGPoint(x: annotatedSelection.maxX,
                                                        y: annotatedSelection.maxY)))
        view.rightMouseUp(with: mouse(.rightMouseUp,
                                      at: CGPoint(x: annotatedSelection.maxX,
                                                  y: annotatedSelection.maxY)))
        precondition(completed?.0 == annotatedSelection && completed?.1 == .annotation,
                     "右键框选应进入标注流程")

        // 从冻结图中裁出的小图可直接进入原有标注导出，不包含遮罩和工具条。
        let crop = CaptureService.crop(white, globalRect: selection, screenFrame: screen, scale: 1)!
        let canvas = AnnotationView(frame: screen, image: crop, selectionRect: selection, scale: 1)
        precondition(rgba(canvas.exportImage()!) == rgba(crop), "无标注导出必须保留截图像素")
        canvas.tool = .box
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 60, y: 60)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 140, y: 100)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 140, y: 100)))
        precondition(rgba(canvas.exportImage()!) != rgba(crop), "标注必须合成进导出图片")
        canvas.undo()
        precondition(rgba(canvas.exportImage()!) == rgba(crop), "撤销应恢复原图")
        print("通过：\(checks) 个逐像素裁剪场景、无效选区、独立图像存储、冻结画面渲染、框选/取消及标注导出/撤销")
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                         count: image.width * image.height * 4))
    }

    private final class ReleaseProbe {
        var released = false
    }

    private static func detachedCrop(probe: ReleaseProbe) -> CGImage {
        let size = 100 * 100 * 4
        let pixels = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        pixels.initializeMemory(as: UInt8.self, repeating: 255, count: size)
        let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(probe).toOpaque(),
                                      data: pixels, size: size) { info, data, _ in
            Unmanaged<ReleaseProbe>.fromOpaque(info!).takeRetainedValue().released = true
            UnsafeMutableRawPointer(mutating: data).deallocate()
        }!
        let image = CGImage(width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        return CaptureService.crop(image, globalRect: CGRect(x: 10, y: 10, width: 20, height: 20),
                                   screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)!
    }

    private static func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @MainActor
    private static func render(_ view: NSView) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
                                  pixelsHigh: Int(view.bounds.height), bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
