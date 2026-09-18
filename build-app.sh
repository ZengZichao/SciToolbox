#!/bin/bash
# SciToolbox .app 打包脚本（本地开发用，ad-hoc 签名）
#
# ⚠️ 本脚本用于「本地跑起来」——产出的裸 .app **不能上传 App Store**。
#    上架走 Xcode 工程：SciToolbox.xcodeproj → xcodebuild archive → exportArchive。
#
# 用法：./build-app.sh
#       SWIFT_BUILD_FLAGS="--arch arm64 --arch x86_64" ./build-app.sh   # 通用二进制
# 输出：build/SciToolbox.app
#
# .github/workflows/release.yml 复用本脚本（传 SWIFT_BUILD_FLAGS 出通用二进制），
# 再把产物打成 .dmg 挂到 GitHub Release。

set -e

cd "$(dirname "$0")"

APP_NAME="SciToolbox"
BUNDLE_ID="com.scitoolbox.app"
MARKETING_VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_MACOS="15.0"

BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

INFO_PLIST_SRC="App/Info.plist"

BUILD_FLAGS=(-c release --disable-sandbox)
if [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
    read -r -a EXTRA_FLAGS <<< "$SWIFT_BUILD_FLAGS"
    BUILD_FLAGS+=("${EXTRA_FLAGS[@]}")
fi

echo "🔨 编译 release 版本（${BUILD_FLAGS[*]}）..."
swift build "${BUILD_FLAGS[@]}"

BIN_PATH=$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)
EXECUTABLE="$BIN_PATH/$APP_NAME"

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ 编译产物未找到：$EXECUTABLE"
    exit 1
fi

if [ ! -f "$INFO_PLIST_SRC" ]; then
    echo "❌ 未找到 $INFO_PLIST_SRC"
    exit 1
fi

echo "📦 组装 .app 包..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

# Info.plist 的权威副本在 App/Info.plist，用 Xcode 构建设置变量书写。
# 本地开发场景没有构建设置可注入，这里把变量替换为字面值。
echo "📝 展开 Info.plist 变量..."
sed -e "s|\$(PRODUCT_NAME)|$APP_NAME|g" \
    -e "s|\$(EXECUTABLE_NAME)|$APP_NAME|g" \
    -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$BUNDLE_ID|g" \
    -e "s|\$(MARKETING_VERSION)|$MARKETING_VERSION|g" \
    -e "s|\$(CURRENT_PROJECT_VERSION)|$BUILD_NUMBER|g" \
    -e "s|\$(MACOSX_DEPLOYMENT_TARGET)|$MIN_MACOS|g" \
    "$INFO_PLIST_SRC" > "$CONTENTS_DIR/Info.plist"

# 本地包用 .icns 直挂图标。App Store 包走 Assets.car + CFBundleIconName，
# 不需要、也不应保留 CFBundleIconFile。
if [ -f "AppIcon.icns" ]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist"
fi

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo "✅ 图标已添加"
else
    echo "ℹ️  未找到 AppIcon.icns，使用系统默认图标"
fi

if [ -f "AppIcon_1024.png" ]; then
    cp "AppIcon_1024.png" "$RESOURCES_DIR/AppIcon_1024.png"
    echo "✅ 界面内 logo 已添加"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null && echo "✅ Info.plist 语法校验通过"

# 签名（App Store / 分发）：
#   - 默认 ad-hoc 本地跑；正式发布时设环境变量，例如：
#       SIGN_IDENTITY="Apple Distribution: 你的名字 (TEAMID)" ./build-app.sh
#   - 强制开启硬连运行时（--options runtime）与 App Sandbox 权限
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "🔏 签名（identity=${SIGN_IDENTITY}）..."
if [ -n "${PROVISIONING_PROFILE:-}" ] && [ -f "$PROVISIONING_PROFILE" ]; then
    cp "$PROVISIONING_PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"
    echo "   ├ 已嵌入 provisioning profile"
fi

codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements App/SciToolbox.entitlements \
    --options runtime \
    "$APP_DIR"
echo "   └ 校验："
codesign --verify --deep --strict "$APP_DIR" && echo "   ✓ 签名校验通过"
codesign -d --entitlements - "$APP_DIR" 2>/dev/null | grep -E "app-sandbox|network.client|user-selected" || true

echo ""
echo "✅ 打包完成！"
echo "   位置：$APP_DIR"
echo ""
echo "   安装到 /Applications："
echo "   cp -R $APP_DIR /Applications/"
echo ""
echo "   直接运行（ad-hoc 签名需右键打开或 xattr -dr com.apple.quarantine）："
echo "   open $APP_DIR"
echo ""
echo "   上架 App Store 请改用 Xcode 工程（本脚本产物不可上传）："
echo "   xcodebuild -project SciToolbox.xcodeproj -scheme SciToolbox -configuration Release \\"
echo "     -destination 'generic/platform=macOS' -archivePath build/SciToolbox.xcarchive \\"
echo "     -allowProvisioningUpdates archive"
