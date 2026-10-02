# ScreenShot 截图工具

一个 macOS 原生截图标注工具，用 **Swift + AppKit + ScreenCaptureKit** 构建，零第三方依赖。
全局快捷键触发、区域框选、两种模式、标注、钉图、自动保存、可选白色圆角边框。

> 项目位置：`~/ScreenShotPrototype`

---

## 功能

### 两种截图模式

| 模式 | 默认快捷键 | 行为 |
|------|-----------|------|
| **快捷模式** | `⌥A` | 框选 → 截图 → **直接复制到剪贴板**（不保存、不打扰） |
| **正常模式** | `⌥S` | 框选 → 截图 → **进入标注编辑器** |

### 菜单栏截图入口

- **截全屏**：截取鼠标所在屏幕的完整画面并复制到剪贴板。
- **截我选中的窗口**：打开 macOS 系统窗口选择器，选定一个窗口后只截取该窗口并复制到剪贴板；选择器会隐藏本工具自身，避免误截菜单栏应用。

快捷键可在「设置」窗口（菜单栏图标 → 设置… 或 `⌘,`）里自定义，改完立即生效、持久化。

### 标注编辑器（正常模式）

截图后在选区下方弹出浮动工具条：

`直线` · `箭头` · `方框` · `文字` ｜ `撤销` · `钉图` · `复制` · `保存` · `取消`

- 直线 / 箭头 / 方框：在图上拖拽绘制
- 文字：点击位置出现输入框，回车确认
- 复制：截图 + 标注**合成后**进剪贴板
- 保存：直接存到设置里的目录（时间戳命名），不弹框
- 钉图：把截图**钉在屏幕上**（浮动置顶，可拖动 / 滚轮缩放 / `Esc`·双击·右键关闭）
- `⌘Z` 撤销，`Esc` 取消整个截图

### 工具栏快捷键（截图模式内）

| 键 | 动作 |
|----|------|
| `1` | 钉图 |
| `2` | 复制 |
| `3` | 保存 |

默认 1/2/3，可在设置里改（支持单键或带修饰键），按钮右下角会显示当前键。

### 其它

- **白色圆角边框**：可在设置开关，宽度用滑块自定义（应用于复制/保存/钉图/快捷复制）
- **自定义保存目录**：设置里选目录，点「保存」自动落盘
- **全 Retina 分辨率**：整屏全像素截取后像素级裁剪，标注按 `backingScaleFactor` 合成，绝不发虚
- **保留菜单与临时画面**：按截图快捷键后先捕获当前屏幕，再显示框选窗口，在静止画面上选择区域。整屏快照仅在内存中保留，完成或取消框选后释放，不自动保存到磁盘。
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
| 绘制 / 导出 | Core Graphics · `NSBezierPath` · `CGContext` · `NSBitmapImageRep` |

---

## 项目结构

```
ScreenShotPrototype/
├── build.sh                    # 编译 + 签名，产出 ScreenShot.app
├── package-dmg.sh              # 一键打包 DMG（先编译再打包）
├── make-icon.sh                # 把 Icon.png 转成应用图标 AppIcon.icns
├── Icon.png                    # 应用图标源图（可替换）
├── Info.plist                  # 应用配置（菜单栏应用、最低 macOS 14、图标名）
├── docs/项目总结.html          # 项目实现/签名/分发的图文总结
├── README.md
└── Sources/
    ├── main.swift                       # 入口，.accessory 模式启动
    ├── AppDelegate.swift                # 编排中心：菜单栏/快捷键/模式分支/持有钉图
    │
    ├── HotKeyManager.swift              # 全局快捷键封装（Carbon）
    ├── KeyCodeMap.swift                 # 键码↔字符、Cocoa↔Carbon 修饰键转换
    ├── Settings.swift                   # 所有设置的持久化（UserDefaults）
    ├── HotKeyRecorderView.swift         # 快捷键录制控件（单键/强制修饰键）
    ├── SettingsWindowController.swift   # 设置窗口（从上而下自动排版）
    │
    ├── OverlayController.swift          # 全屏遮罩窗口（置顶、可成 key）
    ├── SelectionView.swift             # 框选交互 + 绘制 + 十字光标
    ├── CaptureService.swift            # 整屏截取 + 像素级裁剪 + 坐标换算
    │
    ├── Annotation.swift                 # 标注模型（线/箭头/框/文字）+ 绘制
    ├── AnnotationView.swift             # 标注画布 + 全分辨率合成导出
    ├── AnnotationEditorController.swift # 标注编辑器窗口 + 工具条 + 快捷键
    │
    ├── PinController.swift              # 钉图浮动窗口（拖动/缩放/关闭）
    ├── ImageDecorator.swift             # 白色圆角边框
    └── ImageSaver.swift                 # 存 PNG 到指定目录
```

### 核心流程

```
全局快捷键 / 菜单栏触发
        │
        ▼
CaptureService.capture              ← 激活窗口之前捕获整屏，暂存内存
        │
        ▼
OverlayController + SelectionView   ← 在冻结画面上拖拽框选
        │  (完成或取消后释放整屏快照)
        ▼
CaptureService.crop                 ← 裁剪并复制选区为独立图片
        │
   ┌────┴────┐
   ▼         ▼
快捷模式     正常模式
复制剪贴板   AnnotationEditorController ← 标注 → 复制/保存/钉图（可选白边）

截全屏 / 截我选中的窗口
        │
        ▼
CaptureService / macOS 窗口选择器 → 直接复制图片
```

---

## 构建与运行（开发者）

```bash
cd ~/ScreenShotPrototype
./build.sh          # 编译并签名，产出 ScreenShot.app
open ScreenShot.app
```

构建产物 `ScreenShot.app`、`*.dmg`、`AppIcon.icns` 不纳入版本控制（见 `.gitignore`）。

运行 `bash test.sh` 可验证快照的像素裁剪、Retina/副屏坐标、冻结画面绘制、取消和标注导出；测试使用合成图片，不截取用户屏幕或修改剪贴板。真实菜单截图需打开目标软件菜单后，用全局快捷键验证；点击本工具菜单栏入口本身可能已使目标菜单关闭。

### 关于权限与签名

- 首次运行需在 **系统设置 › 隐私与安全性 › 屏幕录制** 中授权，授权后**重启 app** 生效。
- `build.sh` 使用本地自签名证书 `ScreenShot Dev Cert` 签名，使屏幕录制授权绑定到「证书 + Bundle ID」，**重新编译后不会丢失权限**。
  - 该证书仅为本地开发用，**未**设为系统受信任根。
  - 若证书不存在，脚本会回退到临时签名（每次编译都会重新请求权限）。

---

## 脚本说明

### `build.sh` — 编译 + 签名

```bash
./build.sh
```

编译 `Sources/` 下所有 Swift 文件，组装成 `ScreenShot.app`，用自签名证书签名；若存在 `AppIcon.icns` 会自动嵌入图标。

### `make-icon.sh` — 修改应用图标

把一张方形 PNG 转成 macOS 应用图标。**换图标只需 3 步**：

```bash
# 1) 把你的图标放到项目根目录，命名 Icon.png（建议 1024×1024 方形）
#    或直接指定：./make-icon.sh 你的图.png
# 2) 生成 AppIcon.icns（自动切出 16~512 各档位含 @2x）
./make-icon.sh
# 3) 重新构建或打包，图标即生效
./build.sh           # 或 ./package-dmg.sh
```

> 图标没立刻更新？macOS 会缓存图标，执行 `touch ScreenShot.app && killall Finder` 刷新，必要时注销重登。
> 注意：这是**应用本体图标**；菜单栏那个小图标是代码里的 SF Symbol，与此无关。

### `package-dmg.sh` — 打包 DMG 分发

```bash
./package-dmg.sh
```

自动：编译签名 → 把 App 和「应用程序」快捷方式放进 DMG → 产出 `ScreenShot.dmg`。
**每次改完代码跑这一个脚本，把生成的 `ScreenShot.dmg` 发给朋友即可。**

---

## 分发给朋友使用

> 当前未加入 Apple Developer Program，**无法公证（notarize）**，所以朋友首次打开会被系统拦截，需手动放行一次（之后正常使用）。这对少数朋友/同事完全够用，免费。

### 你要做的（发布方）

```bash
./package-dmg.sh          # 产出 ScreenShot.dmg
```

把 `ScreenShot.dmg` 通过 AirDrop / 网盘 / 邮件发给朋友。

### 朋友要做的（接收方，只需放行一次）

**第 1 步：安装**

打开 DMG，把 `ScreenShot` 拖进「应用程序」。

**第 2 步：放行（二选一）**

▸ **方式 A — 图形界面（推荐给不懂命令行的人）**

1. 双击 App，弹出「无法打开，因为 Apple 无法验证…」，先**点取消/关闭**
2. 打开 **系统设置（System Settings）**
3. 左侧进入 **隐私与安全性（Privacy & Security）**
4. 滚动到底部「安全性」区域，会看到一行 *"已阻止使用 ScreenShot…"*
5. 点右侧 **「仍要打开」（Open Anyway）**
6. 弹窗再点一次 **「仍要打开」**，输入开机密码 → 成功打开

> 注：macOS Sequoia（15）已移除旧的「右键 → 打开」方式，必须走上面的「系统设置 › 隐私与安全性 › 仍要打开」。

▸ **方式 B — 命令行（懂技术、信任发布者的人最快）**

```bash
xattr -dr com.apple.quarantine /Applications/ScreenShot.app
```

直接去掉「隔离」标记，之后双击正常打开，无任何提示。

**第 3 步：授权屏幕录制**

第一次截图时，按提示到 **系统设置 › 隐私与安全性 › 屏幕录制** 勾选 **ScreenShot**，然后**重新打开 App**。

### 体验对比

| | 现在（未公证） | 加入开发者计划 + 公证后 |
|---|---|---|
| 能否分发 | ✅ 能 | ✅ 能 |
| 朋友体验 | 需「仍要打开」放行一次 | 双击直接打开，无提示 |
| 成本 | 0 元 | $99/年 |

---

## 环境要求

- macOS 14.0+（ScreenCaptureKit `SCScreenshotManager`）
- Xcode / Swift 6 工具链

---

## 后续计划

- [ ] 颜色 / 线宽选择
- [ ] 圆/椭圆、画笔、马赛克、序号标记
- [ ] 标注的选中 / 拖动 / 删除
- [ ] 图片阴影开关
- [ ] OCR 文字识别（Vision 框架）
- [ ] 多屏支持优化
- [ ] 加入开发者计划后：Developer ID 签名 + 公证，免去朋友手动放行
```
