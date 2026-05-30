#!/bin/bash
# 一键打包 DMG：先编译签名（调用 build.sh），再生成可拖拽安装的 DMG。
# 用法：./package-dmg.sh
set -e
cd "$(dirname "$0")"

APP="ScreenShot.app"
DMG="ScreenShot.dmg"
VOL="ScreenShot"
STAGE="$(mktemp -d)"

# 1) 编译 + 签名
echo "▶︎ 编译中…"
./build.sh

if [ ! -d "$APP" ]; then
  echo "❌ 没找到 $APP，构建可能失败了"; exit 1
fi

# 2) 准备 DMG 内容：App + 「应用程序」快捷方式（方便拖拽安装）
echo "▶︎ 打包 DMG…"
cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

# 3) 生成压缩 DMG（覆盖旧的）
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$STAGE"

SIZE=$(du -h "$DMG" | cut -f1)
echo ""
echo "✅ 完成：$(pwd)/$DMG  ($SIZE)"
echo "   把这个 .dmg 发给朋友即可。"
echo ""
echo "ℹ️  朋友首次打开会被系统拦截（未公证），需放行一次："
echo "   系统设置 › 隐私与安全性 › 「仍要打开」"
echo "   或终端执行： xattr -dr com.apple.quarantine /Applications/ScreenShot.app"
