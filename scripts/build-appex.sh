#!/bin/bash
# 编译访达扩展可执行文件（appex 的 Contents/MacOS/ 产物）
# 用法： ./scripts/build-appex.sh [arm64|x86_64|universal] [输出路径]
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="${1:-}"
if [ -z "$ARCH" ]; then ARCH=$(uname -m); fi
OUT="${2:-}"
if [ -z "$OUT" ]; then OUT="build/appex/ClipStatsFinder"; fi
DEPLOY_TARGET="macos13.0"
MCACHE="build/mcache"
SOURCES="$(ls Sources/FinderExt/*.swift) Sources/Support/FinderEditors.swift"

mkdir -p build/appex "$(dirname "$OUT")"

build_one() {
  local arch="$1"
  local output="$2"
  swiftc -O -swift-version 5 \
    -module-name ClipStatsFinder \
    -module-cache-path "$MCACHE" \
    -target "$arch-apple-$DEPLOY_TARGET" \
    -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -framework FinderSync -framework Cocoa \
    $SOURCES -o "$output"
}

case "$ARCH" in
  universal)
    build_one arm64 "build/appex/ClipStatsFinder-arm64"
    build_one x86_64 "build/appex/ClipStatsFinder-x86_64"
    lipo -create -output "$OUT" "build/appex/ClipStatsFinder-arm64" "build/appex/ClipStatsFinder-x86_64"
    ;;
  arm64|x86_64)
    build_one "$ARCH" "$OUT"
    ;;
  *)
    echo "不支持的架构：$ARCH" >&2
    exit 1
    ;;
esac

echo "appex binary: $OUT"
