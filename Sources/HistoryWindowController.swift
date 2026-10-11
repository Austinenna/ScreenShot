import AppKit

/// 一条临时截图记录。
///
/// `ScreenshotCache` 可以把自己的记录映射为这个轻量值类型，再交给
/// `HistoryWindowController`。这样历史面板不需要知道缓存使用 actor、文件还是
/// 其他存储方式。
struct ScreenshotHistoryItem: Hashable, Sendable {
    let id: String
    let capturedAt: Date
    let expiresAt: Date
    let source: String
    let width: Int?
    let height: Int?

    init(id: String, capturedAt: Date, expiresAt: Date, source: String,
         width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.expiresAt = expiresAt
        self.source = source
        self.width = width
        self.height = height
    }
}

/// 历史面板所需的最小缓存接口。
///
/// 实际缓存可以是 actor；调用方只要在 adapter 中把记录和 PNG 数据映射到
/// 这里即可。所有写操作完成后，面板会自动刷新；新截图加入缓存时，调用
/// `HistoryWindowController.refresh()` 即可同步到已打开的面板。
protocol ScreenshotHistoryDataSource: AnyObject {
    func fetchItems() async throws -> [ScreenshotHistoryItem]
    func loadImageData(for item: ScreenshotHistoryItem) async throws -> Data
    func delete(item: ScreenshotHistoryItem) async throws
    func clear() async throws
}

/// 最近截图面板。
///
/// UI 只负责列表和用户动作，复制与钉图交由 AppDelegate 通过回调处理。回调
/// 在主线程执行，并接收已经从缓存文件读出的 `NSImage`。
@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    typealias Item = ScreenshotHistoryItem
    typealias Action = (Item, NSImage) -> Void

    private let dataSource: ScreenshotHistoryDataSource
    private let onCopy: Action
    private let onPin: Action

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var clearButton: NSButton!
    private var statusLabel: NSTextField!
    private var scrollView: NSScrollView!
    private var listView: HistoryListView!
    private var rows: [HistoryRowView] = []
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?

    /// - Parameters:
    ///   - dataSource: 文件缓存的 adapter；不要求在主线程实现。
    ///   - onCopy: 用户点「复制」时执行，回调运行在主线程。
    ///   - onPin: 用户点「钉图」时执行，回调运行在主线程。
    init(dataSource: ScreenshotHistoryDataSource,
         onCopy: @escaping Action,
         onPin: @escaping Action) {
        self.dataSource = dataSource
        self.onCopy = onCopy
        self.onPin = onPin

        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
        window.title = "最近截图"
        window.minSize = NSSize(width: 390, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("HistoryWindowController 不支持 storyboard") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTask?.cancel()
        timer?.invalidate()
    }

    // MARK: - Public

    /// 显示面板并加载最新缓存。新截图写入缓存后也可直接调用此方法。
    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        startTimerIfNeeded()
        refresh()
    }

    /// 重新读取索引。此方法是同步触发，实际读取在后台异步完成。
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.dataSource.fetchItems()
                guard !Task.isCancelled else { return }
                self.apply(items: items)
            } catch {
                guard !Task.isCancelled else { return }
                self.applyError("读取截图历史失败")
            }
        }
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        titleLabel = NSTextField(labelWithString: "最近截图")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        subtitleLabel = NSTextField(labelWithString: "正在读取…")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subtitleLabel)

        clearButton = NSButton(title: "立即清空", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(clearButton)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        listView = HistoryListView()
        listView.frame = NSRect(x: 0, y: 0,
                                width: scrollView.contentView.bounds.width,
                                height: scrollView.contentView.bounds.height)
        listView.autoresizingMask = [.width]
        scrollView.documentView = listView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scrollBoundsChanged),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -12),

            clearButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            statusLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24)
        ])
    }

    private func apply(items: [Item]) {
        let sorted = items
            .filter { $0.expiresAt > Date() }
            .sorted { $0.capturedAt > $1.capturedAt }

        refreshTask = nil
        listView.removeAllRows()
        rows.removeAll()
        rows = sorted.map { item in
            let row = HistoryRowView(item: item,
                                     onCopy: { [weak self] row in self?.copy(row: row) },
                                     onPin: { [weak self] row in self?.pin(row: row) },
                                     onDelete: { [weak self] row in self?.delete(row: row) })
            listView.addRow(row)
            loadImage(for: item) { [weak row] image in
                row?.setImage(image)
            }
            return row
        }
        listView.needsLayout = true
        resizeListView()
        updateHeader(count: sorted.count)
        statusLabel.isHidden = !sorted.isEmpty
        statusLabel.stringValue = sorted.isEmpty ? "最近 24 小时没有截图\n按快捷键开始截图" : ""
    }

    private func applyError(_ message: String) {
        refreshTask = nil
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        listView.removeAllRows()
        resizeListView()
        subtitleLabel.stringValue = message
        statusLabel.isHidden = false
        statusLabel.stringValue = message
    }

    private func updateHeader(count: Int) {
        subtitleLabel.stringValue = count == 0
            ? "保留时间为 24 小时"
            : "\(count) 张 · 24 小时后自动删除"
    }

    private func resizeListView() {
        guard let content = scrollView?.contentView else { return }
        let width = max(content.bounds.width, 1)
        let fittingHeight = listView.fittingHeight
        let height = max(content.bounds.height, fittingHeight)
        listView.setFrameSize(NSSize(width: width, height: height))
        listView.needsLayout = true
    }

    // MARK: - Actions

    private func copy(row: HistoryRowView) {
        loadImage(for: row.item) { [weak self, weak row] image in
            guard let self, let row, let image else { return }
            self.onCopy(row.item, image)
        }
    }

    private func pin(row: HistoryRowView) {
        loadImage(for: row.item) { [weak self, weak row] image in
            guard let self, let row, let image else { return }
            self.onPin(row.item, image)
        }
    }

    private func loadImage(for item: Item, completion: @escaping (NSImage?) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.dataSource.loadImageData(for: item)
                let image = NSImage(data: data)
                completion(image)
            } catch {
                self.statusLabel.stringValue = "读取截图失败，请稍后重试"
                self.statusLabel.isHidden = false
                completion(nil)
            }
        }
    }

    private func delete(row: HistoryRowView) {
        let item = row.item
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dataSource.delete(item: item)
                self.refresh()
            } catch {
                self.applyError("删除截图失败")
            }
        }
    }

    @objc private func clearAll() {
        clearButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dataSource.clear()
                self.clearButton.isEnabled = true
                self.refresh()
            } catch {
                self.applyError("清空截图失败")
                self.clearButton.isEnabled = true
            }
        }
    }

    @objc private func scrollBoundsChanged() { resizeListView() }

    // MARK: - Timer / lifecycle

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
    }

}

// MARK: - List and row views

private final class HistoryListView: NSView {
    private(set) var rows: [HistoryRowView] = []
    private let rowHeight: CGFloat = 88
    private let gap: CGFloat = 8
    private let sideInset: CGFloat = 12

    override var isFlipped: Bool { true }

    var fittingHeight: CGFloat {
        guard !rows.isEmpty else { return 24 }
        return sideInset * 2 + CGFloat(rows.count) * rowHeight + CGFloat(max(rows.count - 1, 0)) * gap
    }

    func addRow(_ row: HistoryRowView) {
        rows.append(row)
        addSubview(row)
    }

    func removeAllRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width - sideInset * 2, 120)
        for (index, row) in rows.enumerated() {
            let y = sideInset + CGFloat(index) * (rowHeight + gap)
            row.frame = NSRect(x: sideInset, y: y, width: width, height: rowHeight)
            row.layoutSubtreeIfNeeded()
        }
    }
}

private final class HistoryRowView: NSView {
    let item: ScreenshotHistoryItem
    private let onCopy: (HistoryRowView) -> Void
    private let onPin: (HistoryRowView) -> Void
    private let onDelete: (HistoryRowView) -> Void

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailsLabel = NSTextField(labelWithString: "")
    private let expiryLabel = NSTextField(labelWithString: "")
    private var timer: Timer?

    init(item: ScreenshotHistoryItem,
         onCopy: @escaping (HistoryRowView) -> Void,
         onPin: @escaping (HistoryRowView) -> Void,
         onDelete: @escaping (HistoryRowView) -> Void) {
        self.item = item
        self.onCopy = onCopy
        self.onPin = onPin
        self.onDelete = onDelete
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        buildUI()
        updateExpiry()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.updateExpiry()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    func setImage(_ image: NSImage?) {
        imageView.image = image ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "截图")
    }

    private func buildUI() {
        imageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "截图")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .grayBezel
        imageView.contentTintColor = .secondaryLabelColor
        addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        detailsLabel.font = .systemFont(ofSize: 11)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailsLabel)

        expiryLabel.font = .systemFont(ofSize: 11)
        expiryLabel.textColor = .secondaryLabelColor
        addSubview(expiryLabel)

        let copy = button("复制", #selector(copyAction))
        let pin = button("钉图", #selector(pinAction))
        let remove = button("删除", #selector(deleteAction))
        addSubview(copy); addSubview(pin); addSubview(remove)
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 11)
        b.setButtonType(.momentaryPushIn)
        return b
    }

    override func layout() {
        super.layout()
        let thumbW: CGFloat = 96
        imageView.frame = NSRect(x: 10, y: 10, width: thumbW, height: bounds.height - 20)
        let textX = imageView.frame.maxX + 12
        let buttonW: CGFloat = 48
        let buttonGap: CGFloat = 5
        let buttonY = bounds.height - 32
        let remove = subviews.last!
        let pin = subviews[subviews.count - 2]
        let copy = subviews[subviews.count - 3]
        remove.frame = NSRect(x: bounds.width - 10 - buttonW, y: buttonY, width: buttonW, height: 24)
        pin.frame = NSRect(x: remove.frame.minX - buttonGap - buttonW, y: buttonY, width: buttonW, height: 24)
        copy.frame = NSRect(x: pin.frame.minX - buttonGap - buttonW, y: buttonY, width: buttonW, height: 24)

        let textW = max(30, copy.frame.minX - textX - 10)
        titleLabel.frame = NSRect(x: textX, y: 10, width: textW, height: 18)
        detailsLabel.frame = NSRect(x: textX, y: 31, width: textW, height: 16)
        expiryLabel.frame = NSRect(x: textX, y: 50, width: textW, height: 16)
    }

    private func updateExpiry() {
        let remaining = item.expiresAt.timeIntervalSinceNow
        if remaining <= 0 {
            expiryLabel.stringValue = "即将删除"
            expiryLabel.textColor = .systemOrange
        } else {
            expiryLabel.stringValue = "还剩 \(Self.formatRemaining(remaining))"
            expiryLabel.textColor = remaining < 3600 ? .systemOrange : .secondaryLabelColor
        }

        titleLabel.stringValue = Self.formatDate(item.capturedAt)
        let source = item.source.isEmpty ? "截图" : item.source
        if let width = item.width, let height = item.height {
            detailsLabel.stringValue = "\(source) · \(width) × \(height)"
        } else {
            detailsLabel.stringValue = source
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "今天 HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            f.dateFormat = "昨天 HH:mm"
        } else {
            f.dateFormat = "MM 月 dd 日 HH:mm"
        }
        return f.string(from: date)
    }

    private static func formatRemaining(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 1)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
        if minutes > 0 { return "\(minutes) 分钟" }
        return "不到 1 分钟"
    }

    @objc private func copyAction() { onCopy(self) }
    @objc private func pinAction() { onPin(self) }
    @objc private func deleteAction() { onDelete(self) }
}
