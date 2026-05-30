#!/bin/bash
# 把一张方形 PNG 转成 macOS 应用图标 AppIcon.icns
# 用法：./make-icon.sh [源图，默认 Icon.png]   建议 1024x1024
set -e
cd "$(dirname "$0")"

SRC="${1:-Icon.png}"
if [ ! -f "$SRC" ]; then
  echo "❌ 找不到源图：$SRC"
  echo "   请放一张 1024x1024 的方形 PNG（命名 Icon.png），或：./make-icon.sh 你的图.png"
  exit 1
fi

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"; mkdir "$ICONSET"

# 生成各档位尺寸（含 @2x Retina）
for s in 16 32 128 256 512; do
  sips -z $s $s        "$SRC" --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"

echo "✅ 已生成 AppIcon.icns"
echo "   接着运行 ./build.sh 或 ./package-dmg.sh，图标即生效。"
