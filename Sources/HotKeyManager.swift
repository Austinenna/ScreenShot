import AppKit
import Carbon

/// 全局快捷键管理（Carbon RegisterEventHotKey，系统级，无需辅助功能权限）
final class HotKeyManager {
    static let shared = HotKeyManager()

    private struct Entry {
        var ref: EventHotKeyRef?
        var handler: () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {}

    /// 注册一个全局快捷键，返回内部 id（用于注销）
    @discardableResult
    func register(keyCode: UInt16, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1

        let hkID = EventHotKeyID(signature: OSType(0x53534854) /* 'SSHT' */, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            print("RegisterEventHotKey 失败: \(status)")
        }
        entries[id] = Entry(ref: ref, handler: handler)
        return id
    }

    func unregister(_ id: UInt32) {
        if let e = entries[id], let ref = e.ref {
            UnregisterEventHotKey(ref)
        }
        entries[id] = nil
    }

    func unregisterAll() {
        for (id, _) in entries { unregister(id) }
    }

    fileprivate func fire(id: UInt32) {
        entries[id]?.handler()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            mgr.fire(id: hkID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
