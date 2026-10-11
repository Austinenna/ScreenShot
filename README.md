# ScreenShot 截图工具

一个 macOS 原生截图标注工具，用 **Swift + AppKit + ScreenCaptureKit** 构建，零第三方依赖。
全局快捷键触发、区域框选、三种模式、标注、钉图、OCR 文字复制、自动保存、可选白色圆角边框。

> 项目位置：`~/ScreenShotPrototype`

---

## 功能

### 三种截图模式

| 模式 | 默认快捷键 | 行为 |
|------|-----------|------|
| **快捷模式** | `⌥A` | 框选 → 截图 → **直接复制到剪贴板**（不写入用户保存目录） |
| **正常模式** | `⌥S` | 框选 → 截图 → **进入标注编辑器** |
| **文字识别模式** | `⌥3` | 框选 → 原生 OCR 识别中英文 → **直接复制纯文本**（不进入标注） |

菜单栏另外提供两种直接复制的截图入口：

- **截全屏**（默认 `⌥4`）：截取鼠标所在屏幕的完整画面并复制到剪贴板。
- **截我选中的窗口**（默认 `⌥5`）：打开 macOS 系统窗口选择器，选定一个窗口后只截取该窗口并复制到剪贴板；截图选择器会隐藏本工具自身，避免误截菜单栏应用。

五个全局截图入口的快捷键都可在「设置」窗口（菜单栏图标 → 设置… 或 `⌘,`）里自定义，改完立即生效、持久化。

### 最近 24 小时截图历史

图片型截图会自动写入应用专用的临时缓存，并在菜单栏选择「最近截图…」打开历史面板。缓存使用本地 PNG 文件加 `index.json` 内存索引，默认目录为 `~/Library/Application Support/ScreenShot/Cache/`，不写入用户设置的长期保存目录。

- 历史面板显示缩略图、截图时间、来源、尺寸和剩余有效时间
- 可从历史记录重新复制、钉图或删除单条记录，也可立即清空全部缓存
- 每条记录从最终图片生成时开始保留 24 小时；复制和钉图不会延长时间
- 到期后删除缓存文件和索引记录；由该记录创建的钉图也会关闭
- 应用启动、打开历史、定时器和系统唤醒时都会按绝对时间清理过期记录
- 标注模式在点击复制、保存或钉图后缓存最终合成图；取消编辑不会进入历史
- 文字识别模式默认只复制文字，不保存原图；用户主动点击「保存」的文件不受缓存清理影响

缓存文件只由本应用管理。已经粘贴到其他应用或同步剪贴板的副本无法由本应用撤回。

### OCR 文字识别

按 `Option+3`，框选需要提取文字的区域，松开后使用苹果原生 **Vision** 框架在后台识别，完成后直接复制到系统剪贴板，并在菜单栏提示「已复制文字」。菜单栏也有文字识别入口，快捷键可以在设置中的「全局快捷键」调整。

支持普通横排中英文截图（含简体、繁体和混排），输出按行排列的纯文本；暂不还原表格、复杂多栏布局或公式。图片仅在本机内存中处理，不上传、不自动落盘。未识别到文字或识别失败时显示提示，保留原剪贴板内容。识别期间暂不接受新的截图，避免识别结果相互覆盖。

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
| 文字识别 | Vision（`VNRecognizeTextRequest`，本机中英文识别） |
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
    ├── OCRService.swift                # 原生文字识别、行顺序整理、纯文本复制
    ├── ScreenshotCache.swift           # PNG 文件 + index.json 临时缓存与 24 小时清理
    ├── ScreenshotCacheHistoryDataSource.swift # 缓存 actor 到历史面板的数据适配
    ├── HistoryWindowController.swift   # 最近截图历史面板
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
   ┌────┼───────────────────┐
   ▼    ▼                   ▼
快捷模式 正常模式             文字识别模式（⌥3）
复制图片 标注→复制/保存/钉图    OCRService→复制文字

截全屏 / 截我选中的窗口
        │
        ▼
CaptureService / macOS 窗口选择器 → 直接复制图片

所有图片型输出
        │
        ▼
ScreenshotCache → PNG + index.json → 最近截图历史 → 复制 / 钉图 / 删除
```

---

## 构建与运行（开发者）

```bash
cd ~/ScreenShotPrototype
./build.sh          # 编译并签名，产出 ScreenShot.app
open ScreenShot.app
```

构建产物 `ScreenShot.app`、`*.dmg`、`AppIcon.icns` 不纳入版本控制（见 `.gitignore`）。

运行 `bash test.sh` 可验证快照的像素裁剪、Retina/副屏坐标、冻结画面绘制、取消、标注导出，以及文件缓存的 PNG/index 恢复和 24 小时过期清理；测试使用合成图片，不截取用户屏幕或修改剪贴板。真实菜单截图需打开目标软件菜单后，用全局快捷键验证；点击本工具菜单栏入口本身可能已使目标菜单关闭。

测试还会真实调用 Vision，验证中英文混排识别、1x/2x 图片、空白图片、文本顺序，并使用独立测试剪贴板验证纯文本复制及空结果保护。Vision 测试需能访问系统识别服务，受限执行环境可能需要在正常本机权限下运行。

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
- [x] OCR 文字识别（Vision 框架，⌥3 框选后直接复制中英文纯文本）
- [ ] 多屏支持优化
- [ ] 加入开发者计划后：Developer ID 签名 + 公证，免去朋友手动放行
```
