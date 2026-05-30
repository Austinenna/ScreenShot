import Cocoa

// 入口：以「附件」模式运行（不占用 Dock 图标，只有菜单栏图标）
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
