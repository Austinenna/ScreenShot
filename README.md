# ScreenShot 截图工具（原型 v1）

一个 macOS 原生截图工具的最小可用原型，用 **Swift + AppKit + ScreenCaptureKit** 构建。
支持全局快捷键触发、区域框选、两种截图模式、标注编辑、复制 / 保存。

> 项目位置：`~/ScreenShotPrototype`

---

## 功能

### 两种截图模式

| 模式 | 默认快捷键 | 行为 |
|------|-----------|------|
| **快捷模式** | `⌥A` | 框选 → 截图 → **直接复制到剪贴板**（不保存、不打扰） |
| **正常模式** | `⌥S` | 框选 → 截图 → **进入标注编辑器** |

快捷键可在「设置」窗口（菜单栏图标 → 设置… 或 `⌘,`）里自定义，修改后立即生效，持久化保存。

### 标注编辑器（正常模式）

截图后在选区下方弹出浮动工具条：

`直线` · `方框` · `文字` ｜ `撤销` · `复制` · `保存` · `取消`

- 直线 / 方框：在图上拖拽绘制
- 文字：点击位置出现输入框，回车确认
- 复制：截图 + 标注**合成后**进剪贴板
- 保存：弹出保存对话框，导出 PNG
- `⌘Z` 撤销，`Esc` 取消整个截图

### 其它

- **全 Retina 分辨率**：整屏全像素截取后做像素级裁剪，标注按 `backingScaleFactor` 合成，绝不发虚
- **菜单栏常驻**：无 Dock 图标（`LSUIElement`），通过菜单栏 📷 图标操作
- **全局快捷键**：基于 Carbon `RegisterEventHotKey`，系统级生效，无需辅助功能权限

---

## 技术栈

| 领域 | 技术 |
|------|------|
| 语言 / UI | Swift 6 · AppKit |
| 屏幕截取 | ScreenCaptureKit（`SCScreenshotManager`，macOS 14+） |
| 全局快捷键 | Carbon `RegisterEventHotKey` |
| 设置持久化 | `UserDefaults` |
| 绘制 / 导出 | Core Graphics · `NSBezierPath` · `NSBitmapImageRep` |

---

## 项目结构

```
ScreenShotPrototype/
├── build.sh                    # 编译 + 签名脚本（一键产出 ScreenShot.app）
├── Info.plist                  # 应用配置（菜单栏应用、最低 macOS 14）
├── README.md
└── Sources/
    ├── main.swift                       # 入口，.accessory 模式启动
    ├── AppDelegate.swift                # 编排中心：菜单栏、快捷键、模式分支
    │
    ├── HotKeyManager.swift              # 全局快捷键封装（Carbon）
    ├── KeyCodeMap.swift                 # 键码↔字符、Cocoa↔Carbon 修饰键转换
    ├── Settings.swift                   # 两个快捷键的持久化（UserDefaults）
    ├── HotKeyRecorderView.swift         # 快捷键录制控件
    ├── SettingsWindowController.swift   # 设置窗口
    │
    ├── OverlayController.swift          # 全屏遮罩窗口（置顶、可成 key）
    ├── SelectionView.swift             # 框选交互 + 绘制（暗化/边框/把手/尺寸/十字光标）
    ├── CaptureService.swift            # ScreenCaptureKit 截图 + 坐标换算 + 像素级裁剪
    │
    ├── Annotation.swift                 # 标注模型（直线/方框/文字）+ 绘制
    ├── AnnotationView.swift             # 标注画布 + 全分辨率合成导出
    ├── AnnotationEditorController.swift # 标注编辑器窗口 + 工具条
    └── ImageSaver.swift                 # 存 PNG 到桌面
```

### 核心流程

```
全局快捷键 / 菜单栏触发
        │
        ▼
OverlayController + SelectionView   ← 全屏遮罩，拖拽框选
        │  (返回选区)
        ▼
CaptureService                      ← 整屏全像素截取 → 像素级裁剪
        │
   ┌────┴────┐
   ▼         ▼
快捷模式     正常模式
复制剪贴板   AnnotationEditorController ← 标注 → 复制 / 保存
```

---

## 构建与运行

```bash
cd ~/ScreenShotPrototype
./build.sh          # 编译并签名，产出 ScreenShot.app
open ScreenShot.app
```

构建产物 `ScreenShot.app` 不纳入版本控制（见 `.gitignore`）。

### 关于权限与签名

- 首次运行需在 **系统设置 › 隐私与安全性 › 屏幕录制** 中授权，授权后**重启 app** 生效。
- `build.sh` 使用本地自签名证书 `ScreenShot Dev Cert` 签名，使屏幕录制授权绑定到「证书 + Bundle ID」，**重新编译后不会丢失权限**。
  - 该证书仅为本地开发用，**未**设为系统受信任根。
  - 若证书不存在，脚本会回退到临时签名（每次编译都会重新请求权限）。

---

## 环境要求

- macOS 14.0+（ScreenCaptureKit `SCScreenshotManager`）
- Xcode / Swift 6 工具链

---

## 后续计划

- [ ] 箭头、圆/椭圆、画笔、马赛克、序号标记
- [ ] 颜色 / 线宽选择
- [ ] 标注的选中 / 拖动 / 删除
- [ ] 钉图（把截图钉在屏幕上）
- [ ] OCR 文字识别（Vision 框架）
- [ ] 多屏支持优化
```
