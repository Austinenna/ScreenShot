import Foundation
import AppKit

/// 一条临时截图记录。
///
/// `fileName` 只保存相对于缓存目录的文件名，便于缓存目录移动或在不同机器上
/// 读取索引。实际文件是同名的 PNG 文件。
struct ScreenshotCacheRecord: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let createdAt: Date
    let expiresAt: Date
    let source: String
    let fileName: String
    let width: Int?
    let height: Int?

    var isExpired: Bool { expiresAt <= Date() }
}

/// 截图缓存错误。
enum ScreenshotCacheError: Error, LocalizedError {
    case invalidImageData
    case notFound(String)
    case expired(String)
    case invalidRecord
    case fileReadFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "截图数据为空或不是有效的 PNG 数据"
        case .notFound(let id):
            return "找不到截图缓存：\(id)"
        case .expired(let id):
            return "截图缓存已过期：\(id)"
        case .invalidRecord:
            return "截图缓存记录无效"
        case .fileReadFailed(let url, let error):
            return "读取截图缓存失败（\(url.path)）：\(error.localizedDescription)"
        }
    }
}

/// 本地截图文件缓存。
///
/// 缓存由两部分组成：缓存目录中的 UUID PNG 文件和同目录的 `index.json`。内存中的
/// `records` 是常规读取路径；每次初始化、列出、读取或修改时都会清理过期（或已丢失）
/// 的记录。整个类型是 actor，因此截图完成、历史窗口和定时清理可以从不同任务安全调用。
actor ScreenshotCache {
    static let shared = ScreenshotCache()

    static let defaultTTL: TimeInterval = 24 * 60 * 60

    private struct IndexDocument: Codable {
        let version: Int
        let records: [ScreenshotCacheRecord]
    }

    private let directory: URL
    private let indexURL: URL
    private let ttl: TimeInterval
    private var records: [ScreenshotCacheRecord]

    /// 创建缓存。
    ///
    /// 默认路径为 `~/Library/Application Support/ScreenShot/Cache`。传入自定义目录主要
    /// 用于测试；生产调用直接使用 `ScreenshotCache.shared` 即可。
    init(directory: URL? = nil, ttl: TimeInterval = ScreenshotCache.defaultTTL) {
        let defaultDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ScreenShot", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)

        self.directory = directory ?? defaultDirectory
        self.indexURL = self.directory.appendingPathComponent("index.json", isDirectory: false)
        self.ttl = max(0, ttl)
        self.records = []

        // actor 初始化在第一次调用前同步完成，确保应用启动后历史记录已经可用。
        // 初始化阶段若文件系统暂时不可用，后续公开方法仍会重试创建目录并抛出具体错误。
        do {
            try FileManager.default.createDirectory(at: self.directory,
                                                     withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var cacheDirectory = self.directory
            try? cacheDirectory.setResourceValues(values)
            let indexExists = FileManager.default.fileExists(atPath: self.indexURL.path)
            let loaded = try Self.readIndex(from: self.indexURL)
            let startup = Self.pruneStartupRecords(loaded,
                                                   directory: self.directory,
                                                   now: Date())
            self.records = startup.records
            Self.removeOrphanFiles(in: self.directory,
                                   keeping: Set(startup.records.compactMap { Self.safeFileName($0.fileName) }))
            if startup.didChange || !indexExists {
                try? Self.writeIndex(startup.records, to: self.indexURL, directory: self.directory)
            }
        } catch {
            // 不让临时缓存损坏阻止应用启动；首次 add/list 时会恢复或抛出文件系统错误。
            self.records = []
            Self.removeOrphanFiles(in: self.directory, keeping: [])
        }
    }

    /// 返回缓存目录 URL。
    func directoryURL() -> URL { directory }

    /// 使用注入的根目录创建缓存，等价于 `init(directory:ttl:)`。
    /// 测试通常传入临时目录；生产代码使用 `ScreenshotCache.shared`。
    init(rootURL: URL, ttl: TimeInterval = ScreenshotCache.defaultTTL) {
        self.init(directory: rootURL, ttl: ttl)
    }

    /// 返回当前缓存条目，按创建时间从新到旧排列，并先清理过期文件。
    func list(now: Date = Date()) throws -> [ScreenshotCacheRecord] {
        try ensureReady()
        _ = try purgeExpiredSynchronously(now: now, persist: true)
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    /// `list` 的语义别名，方便历史窗口使用。
    func entries(now: Date = Date()) throws -> [ScreenshotCacheRecord] {
        try list(now: now)
    }

    /// 写入 PNG 数据并登记元数据。
    @discardableResult
    func add(pngData: Data,
             source: String = "unknown",
             width: Int? = nil,
             height: Int? = nil,
             now: Date = Date()) throws -> ScreenshotCacheRecord {
        try ensureReady()
        _ = try purgeExpiredSynchronously(now: now, persist: true)
        guard !pngData.isEmpty else { throw ScreenshotCacheError.invalidImageData }

        let id = UUID().uuidString
        let fileName = "\(id).png"
        let imageURL = directory.appendingPathComponent(fileName, isDirectory: false)
        let record = ScreenshotCacheRecord(id: id,
                                           createdAt: now,
                                           expiresAt: now.addingTimeInterval(ttl),
                                           source: source,
                                           fileName: fileName,
                                           width: width,
                                           height: height)

        try atomicWrite(pngData, to: imageURL)
        records.append(record)
        do {
            try writeIndex()
        } catch {
            records.removeAll { $0.id == id }
            try? FileManager.default.removeItem(at: imageURL)
            throw error
        }
        return record
    }

    /// 将 CGImage 编码为 PNG 后写入缓存。
    @discardableResult
    func add(cgImage: CGImage,
             source: String = "unknown",
             now: Date = Date()) throws -> ScreenshotCacheRecord {
        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw ScreenshotCacheError.invalidImageData
        }
        return try add(pngData: png,
                       source: source,
                       width: cgImage.width,
                       height: cgImage.height,
                       now: now)
    }

    /// `add(pngData:)` 的语义别名。
    @discardableResult
    func insert(pngData: Data,
                source: String = "unknown",
                width: Int? = nil,
                height: Int? = nil,
                now: Date = Date()) throws -> ScreenshotCacheRecord {
        try add(pngData: pngData, source: source, width: width, height: height, now: now)
    }

    /// 读取截图 PNG 数据。读取前会清理过期记录。
    func load(id: String, now: Date = Date()) throws -> Data {
        try ensureReady()
        _ = try purgeExpiredSynchronously(now: now, persist: true)
        guard let record = records.first(where: { $0.id == id }) else {
            throw ScreenshotCacheError.notFound(id)
        }
        guard record.expiresAt > now else {
            throw ScreenshotCacheError.expired(id)
        }

        let url = fileURL(for: record)
        do {
            return try Data(contentsOf: url)
        } catch {
            // 缓存文件被用户或清理工具删除时，及时修复 index.json。
            if !FileManager.default.fileExists(atPath: url.path) {
                records.removeAll { $0.id == id }
                try? writeIndex()
            }
            throw ScreenshotCacheError.fileReadFailed(url, error)
        }
    }

    /// 读取截图 PNG 数据的记录重载。
    func load(_ record: ScreenshotCacheRecord, now: Date = Date()) throws -> Data {
        try load(id: record.id, now: now)
    }

    /// `load` 的语义别名。
    func imageData(for id: String, now: Date = Date()) throws -> Data {
        try load(id: id, now: now)
    }

    /// 返回有效记录对应的 PNG URL。调用者可用该 URL 创建 NSImage 或钉图窗口。
    func imageURL(for id: String, now: Date = Date()) throws -> URL {
        try ensureReady()
        _ = try purgeExpiredSynchronously(now: now, persist: true)
        guard let record = records.first(where: { $0.id == id }) else {
            throw ScreenshotCacheError.notFound(id)
        }
        guard FileManager.default.fileExists(atPath: fileURL(for: record).path) else {
            records.removeAll { $0.id == id }
            try writeIndex()
            throw ScreenshotCacheError.notFound(id)
        }
        return fileURL(for: record)
    }

    /// 返回有效记录对应的 PNG URL。
    func imageURL(for record: ScreenshotCacheRecord, now: Date = Date()) throws -> URL {
        try imageURL(for: record.id, now: now)
    }

    /// `imageURL` 的语义别名。
    func url(for id: String, now: Date = Date()) throws -> URL {
        try imageURL(for: id, now: now)
    }

    /// 删除单条记录及其 PNG 文件。
    @discardableResult
    func remove(id: String, now: Date = Date()) throws -> ScreenshotCacheRecord? {
        try ensureReady()
        _ = try purgeExpiredSynchronously(now: now, persist: true)
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        let record = records.remove(at: index)
        let url = fileURL(for: record)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        do {
            try writeIndex()
        } catch {
            // 恢复内存索引；PNG 若已删除则下次启动会自动丢弃这条记录。
            records.insert(record, at: min(index, records.count))
            throw error
        }
        return record
    }

    /// `remove` 的语义别名。
    @discardableResult
    func delete(id: String, now: Date = Date()) throws -> ScreenshotCacheRecord? {
        try remove(id: id, now: now)
    }

    /// 删除所有缓存 PNG 和 index.json 内容，但保留缓存目录本身。
    func clear() throws {
        try ensureReady()
        for record in records {
            let url = fileURL(for: record)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        records.removeAll()
        Self.removeOrphanFiles(in: directory, keeping: [])
        try writeIndex()
    }

    /// 清理过期或已不存在的记录，并返回被清理的元数据。
    @discardableResult
    func purgeExpired(now: Date = Date()) throws -> [ScreenshotCacheRecord] {
        try ensureReady()
        return try purgeExpiredSynchronously(now: now, persist: true)
    }

    /// 当前缓存数量（会先执行 TTL 清理）。
    func count(now: Date = Date()) throws -> Int {
        try list(now: now).count
    }

    // MARK: - Actor 内部实现

    private func ensureReady() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // index.json 可能是在应用未运行时被删除的；将内存状态视为新的空索引。
        if !FileManager.default.fileExists(atPath: indexURL.path) {
            if !records.isEmpty {
                try writeIndex()
            }
        }
    }

    private func fileURL(for record: ScreenshotCacheRecord) -> URL {
        // 记录来自本 actor 的 index，fileName 只会是 UUID.png。仅取 basename，避免旧版
        // 或外部篡改 index 后通过路径穿越访问缓存目录之外的文件。
        directory.appendingPathComponent(Self.safeFileName(record.fileName) ?? ".invalid-record.png",
                                          isDirectory: false)
    }

    private static func safeFileName(_ fileName: String) -> String? {
        let baseName = URL(fileURLWithPath: fileName).lastPathComponent
        guard !baseName.isEmpty,
              baseName != ".",
              baseName != "..",
              baseName == fileName,
              baseName.hasSuffix(".png") else { return nil }
        return baseName
    }

    private func purgeExpiredSynchronously(now: Date, persist: Bool) throws -> [ScreenshotCacheRecord] {
        let removed = records.filter { record in
            guard let fileName = Self.safeFileName(record.fileName) else { return true }
            return record.expiresAt <= now ||
                !FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }
        guard !removed.isEmpty else { return [] }

        let removedIDs = Set(removed.map(\.id))
        records.removeAll { removedIDs.contains($0.id) }
        for record in removed {
            if let fileName = Self.safeFileName(record.fileName) {
                let url = directory.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        if persist { try writeIndex() }
        Self.removeOrphanFiles(in: directory,
                               keeping: Set(records.compactMap { Self.safeFileName($0.fileName) }))
        return removed
    }

    private func writeIndex() throws {
        try Self.writeIndex(records, to: indexURL, directory: directory)
    }

    private static func readIndex(from url: URL) throws -> [ScreenshotCacheRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IndexDocument.self, from: data).records
    }

    private static func pruneStartupRecords(_ records: [ScreenshotCacheRecord],
                                            directory: URL,
                                            now: Date) -> (records: [ScreenshotCacheRecord], didChange: Bool) {
        let valid = records.filter { record in
            guard let fileName = safeFileName(record.fileName) else { return false }
            return record.expiresAt > now &&
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }
        let removed = records.filter { old in !valid.contains(where: { $0.id == old.id }) }
        for record in removed {
            if let fileName = safeFileName(record.fileName) {
                let url = directory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: url)
            }
        }
        return (valid, valid.count != records.count)
    }

    /// 删除崩溃或强制退出遗留的孤儿 PNG 和原子写临时文件。
    /// 缓存目录是应用私有目录，未被 index.json 引用的 PNG 无法判断年龄，按隐私优先清理。
    private static func removeOrphanFiles(in directory: URL, keeping: Set<String>) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                        includingPropertiesForKeys: nil,
                                                                        options: []) else { return }
        for url in urls {
            let name = url.lastPathComponent
            guard name != "index.json" else { continue }
            let isPNG = url.pathExtension.lowercased() == "png"
            let isTemporary = name.hasPrefix(".") && name.hasSuffix(".tmp")
            guard isPNG || isTemporary else { continue }
            guard !keeping.contains(name) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func writeIndex(_ records: [ScreenshotCacheRecord],
                                   to indexURL: URL,
                                   directory: URL) throws {
        let document = IndexDocument(version: 1,
                                     records: records.sorted { $0.createdAt > $1.createdAt })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicWrite(encoder.encode(document), to: indexURL, directory: directory)
    }

    /// 在同一缓存目录中写入临时文件，再用 rename/replace 原子替换目标。
    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try Self.atomicWrite(data, to: destination, directory: directory)
    }

    private static func atomicWrite(_ data: Data, to destination: URL, directory: URL) throws {
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false)
        defer { try? FileManager.default.removeItem(at: temporary) }

        try data.write(to: temporary, options: [.atomic])
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination,
                                                      withItemAt: temporary,
                                                      backupItemName: nil,
                                                      options: [])
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
