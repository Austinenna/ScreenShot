#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="ScreenShot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp Info.plist "$APP/Contents/Info.plist"

# 有图标就嵌进去（AppIcon.icns 由 make-icon.sh 生成）
if [ -f AppIcon.icns ]; then
  mkdir -p "$APP/Contents/Resources"
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

swiftc -O \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/ScreenShot" \
  -framework Cocoa \
  -framework ScreenCaptureKit \
  -framework Carbon

# 用固定的自签名证书签名：TCC 据此把屏幕录制授权绑定到「证书+BundleID」，
# 重新编译也不会掉权限（前提：证书 "ScreenShot Dev Cert" 已在钥匙串里）。
SIGN_ID="ScreenShot Dev Cert"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "⚠️  未找到证书「$SIGN_ID」，回退临时签名（每次编译都会重新要权限）"
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "✅ 已构建 $APP"
echo "运行: open $APP   或   ./ScreenShot.app/Contents/MacOS/ScreenShot"
