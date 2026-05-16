#!/bin/bash
set -euo pipefail

# ============================================================
#  ZenKith 构建 & 发布脚本
#  - Archive → Export (开发签名) → DMG 打包
#  - 可选: 创建 GitHub Release (需安装 gh CLI)
# ============================================================

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="ZenKith.xcodeproj"
SCHEME="ZenKith"
CONFIG="Release"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/ZenKith.xcarchive"
EXPORT_DIR="$BUILD_DIR/$CONFIG"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

# ---------- 读取版本号 ----------
VERSION=$(grep -A10 "name = Release;" "$PROJECT_DIR/$PROJECT_FILE/project.pbxproj" \
    | grep "MARKETING_VERSION" | head -1 | awk -F ' = ' '{print $2}' | tr -d ';')
BUILD=$(grep -A10 "name = Release;" "$PROJECT_DIR/$PROJECT_FILE/project.pbxproj" \
    | grep "CURRENT_PROJECT_VERSION" | head -1 | awk -F ' = ' '{print $2}' | tr -d ';')
DMG_NAME="ZenKith_v${VERSION}.dmg"

echo "========================================"
echo "  ZenKith 构建脚本"
echo "  版本: ${VERSION} (build ${BUILD})"
echo "========================================"
echo ""

# ---------- 1. 清理 ----------
echo "[1/4] 清理旧构建产物..."
rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

# ---------- 2. Archive ----------
echo "[2/4] 归档 Archive (Release)..."
xcodebuild archive \
    -project "$PROJECT_DIR/$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=YAQ48GV4VF

# ---------- 3. Export ----------
echo "[3/4] 导出 App (开发签名)..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

# ---------- 4. 打包 DMG ----------
echo "[4/4] 打包 DMG..."
APP_PATH="$EXPORT_DIR/ZenKith.app"
DMG_PATH="$EXPORT_DIR/$DMG_NAME"

hdiutil create \
    -volname "ZenKith" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH"

echo ""
echo "========================================"
echo "  构建完成!"
echo "  DMG: $DMG_PATH"
echo "========================================"
echo ""

# ---------- 可选: 创建 GitHub Release ----------
# 取消下方注释并确保已安装 gh CLI 且已登录
#
# read -p "是否创建 GitHub Release? (y/n) " -n 1 -r
# echo
# if [[ $REPLY =~ ^[Yy]$ ]]; then
#     gh release create "v${VERSION}" \
#         --repo horsedirty/ZenKith \
#         --title "v${VERSION}" \
#         --notes "增加稳定性" \
#         "$DMG_PATH"
#     echo "Release 已创建: https://github.com/horsedirty/ZenKith/releases/tag/v${VERSION}"
# fi
