#!/bin/bash
# 打包 ClipStats：编译（可选通用二进制）→ 组装 .app → 生成 zip / dmg / 校验和
# 用法：
#   ./scripts/package.sh                 # 只编译当前架构
#   ARCH=universal ./scripts/package.sh  # arm64 + x86_64 通用二进制
#   ARCH=arm64 ./scripts/package.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClipStats"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
ARCH="${ARCH:-$(uname -m)}"
DEPLOY_TARGET="macos13.0"
BUILD="build"
DIST="dist"
APP="$BUILD/$APP_NAME.app"
SOURCES=$(find Sources -name '*.swift')

mkdir -p "$BUILD" "$DIST" "$BUILD/mcache"

swiftc -O -swift-version 5 -module-cache-path "$BUILD/mcache" \
    -target "arm64-apple-${DEPLOY_TARGET}" $SOURCES -o "$BUILD/${APP_NAME}-arm64"

case "$ARCH" in
  universal)
    swiftc -O -swift-version 5 -module-cache-path "$BUILD/mcache" \
        -target "x86_64-apple-${DEPLOY_TARGET}" $SOURCES -o "$BUILD/${APP_NAME}-x86_64"
    lipo -create -output "$BUILD/${APP_NAME}-universal" \
        "$BUILD/${APP_NAME}-arm64" "$BUILD/${APP_NAME}-x86_64"
    BIN="$BUILD/${APP_NAME}-universal"
    ;;
  arm64)
    BIN="$BUILD/${APP_NAME}-arm64"
    ;;
  x86_64)
    swiftc -O -swift-version 5 -module-cache-path "$BUILD/mcache" \
        -target "x86_64-apple-${DEPLOY_TARGET}" $SOURCES -o "$BUILD/${APP_NAME}-x86_64"
    BIN="$BUILD/${APP_NAME}-x86_64"
    ;;
  *)
    echo "不支持的 ARCH: $ARCH（可选 arm64 / x86_64 / universal）" >&2
    exit 1
    ;;
esac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# ad-hoc 签名（没有开发者证书也能本机运行）
codesign --force --sign - --timestamp=none "$APP"

NAME="${APP_NAME}-${VERSION}-macos-${ARCH}"
ZIP_PATH="$(pwd)/$DIST/${NAME}.zip"
DMG_PATH="$(pwd)/$DIST/${NAME}.dmg"
rm -f "$ZIP_PATH" "$DMG_PATH"

# zip：应用位于压缩包根目录，保留可执行权限与符号链接
STAGE_ZIP="$BUILD/zip-stage"
rm -rf "$STAGE_ZIP"; mkdir -p "$STAGE_ZIP"
cp -R "$APP" "$STAGE_ZIP/"
( cd "$STAGE_ZIP" && zip -qryX "$ZIP_PATH" "$APP_NAME.app" )
rm -rf "$STAGE_ZIP"

# dmg：拖拽安装（部分受限环境无法挂载磁盘映像，失败不影响 zip）
STAGE_DMG="$BUILD/dmg-stage"
rm -rf "$STAGE_DMG"; mkdir -p "$STAGE_DMG"
cp -R "$APP" "$STAGE_DMG/"
ln -s /Applications "$STAGE_DMG/Applications"
if hdiutil create -quiet -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGE_DMG" \
    -ov -format UDZO "$DMG_PATH" >/dev/null 2>&1; then
  :
elif diskutil image create from "$STAGE_DMG" --format UDZO \
    --volumeName "${APP_NAME} ${VERSION}" "$DMG_PATH" >/dev/null 2>&1; then
  :
else
  echo "提示: 当前环境无法创建 DMG（磁盘映像权限受限），已跳过" >&2
fi
rm -rf "$STAGE_DMG"

( cd "$DIST" && shasum -a 256 *.zip *.dmg 2>/dev/null > SHA256SUMS.txt || true )

echo "版本: $VERSION   架构: $ARCH"
echo "架构校验: $(lipo -archs "$BIN")"
echo "产物:"
ls -lh "$DIST" | tail -n +2 | awk '{print "  " $9 "  " $5}'
