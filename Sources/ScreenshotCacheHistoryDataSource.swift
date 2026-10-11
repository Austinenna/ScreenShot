import AppKit

/// 把文件缓存 actor 适配为历史面板需要的异步数据源。
final class ScreenshotCacheHistoryDataSource: ScreenshotHistoryDataSource {
    private let cache: ScreenshotCache

    init(cache: ScreenshotCache = .shared) {
        self.cache = cache
    }

    func fetchItems() async throws -> [ScreenshotHistoryItem] {
        try await cache.list().map { record in
            ScreenshotHistoryItem(id: record.id,
                                  capturedAt: record.createdAt,
                                  expiresAt: record.expiresAt,
                                  source: record.source,
                                  width: record.width,
                                  height: record.height)
        }
    }

    func loadImageData(for item: ScreenshotHistoryItem) async throws -> Data {
        try await cache.load(id: item.id)
    }

    func delete(item: ScreenshotHistoryItem) async throws {
        _ = try await cache.remove(id: item.id)
    }

    func clear() async throws {
        try await cache.clear()
    }
}
