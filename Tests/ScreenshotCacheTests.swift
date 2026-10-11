import AppKit

/// 使用临时目录验证文件、索引和 TTL 清理，不触碰用户的应用支持目录。
@main
struct ScreenshotCacheTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenShotCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        let cache = ScreenshotCache(rootURL: root, ttl: 60)
        let png = fixturePNG()
        let record = try await cache.add(pngData: png, source: "区域截图",
                                         width: 16, height: 12, now: now)
        precondition(record.expiresAt == now.addingTimeInterval(60))
        let firstEntries = try await cache.list(now: now)
        precondition(firstEntries.count == 1)
        let loaded = try await cache.load(id: record.id, now: now)
        precondition(loaded == png)
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))

        // 新建 actor 应从同一个 index.json 恢复记录。
        let reopened = ScreenshotCache(rootURL: root, ttl: 60)
        let restored = try await reopened.list(now: now)
        precondition(restored.map(\.id) == [record.id])

        let expired = try await reopened.add(pngData: png, source: "全屏截图",
                                              now: now.addingTimeInterval(-120))
        let afterExpiry = try await reopened.list(now: now)
        precondition(afterExpiry.map(\.id) == [record.id])
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent(expired.fileName).path))

        _ = try await reopened.remove(id: record.id, now: now)
        let afterRemove = try await reopened.list(now: now)
        precondition(afterRemove.isEmpty)
        try await reopened.clear()
        print("通过：截图 PNG、index.json、重启恢复、TTL 过期清理和删除")
    }

    @MainActor
    private static func fixturePNG() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 12,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 12).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
