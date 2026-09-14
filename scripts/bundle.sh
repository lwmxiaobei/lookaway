#!/bin/bash
# 把 SPM 产物组装成可分发的 .app bundle。
# CMHeadphoneMotionManager 必须跑在带 NSMotionUsageDescription 的已签名 bundle 里，
# 裸二进制拿不到「动作与体能训练」权限。
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="lookaway"
EXECUTABLE="LookAway"
BUNDLE_ID="dev.lookaway.app"
VERSION="${VERSION:-0.1.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/$CONFIGURATION"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "==> 构建 ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$ROOT"

echo "==> 组装 bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>$EXECUTABLE</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>lookaway</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSMotionUsageDescription</key>
	<string>lookaway 读取 AirPods 的头部姿态，用来判断你是否正对屏幕。姿态数据只在本机使用，不会离开这台设备。</string>
	<key>NSHumanReadableCopyright</key>
	<string>lookaway</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> 签名"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Apple Development' | head -1 | sed -E 's/.*"(.*)"/\1/')}"

if [ -n "$IDENTITY" ]; then
  echo "    使用身份: $IDENTITY"
  codesign --force --options runtime --sign "$IDENTITY" "$APP_DIR"
else
  echo "    未找到开发者身份，回退到 ad-hoc 签名"
  codesign --force --sign - "$APP_DIR"
fi

codesign --verify --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/    /'
echo "==> 完成: $APP_DIR"
