#!/usr/bin/env bash
# 构建 BetterDictation.app（无需 Xcode，仅需 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="dist/BetterDictation.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product BetterDictation

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/BetterDictation"
[ -x "$BIN" ] || { echo "构建产物不存在: $BIN" >&2; exit 1; }

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BetterDictation"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> 代码签名（ad-hoc）"
codesign --force --sign - \
  --entitlements Resources/BetterDictation.entitlements \
  --identifier io.xrl.BetterDictation \
  "$APP"

codesign --verify --verbose=2 "$APP" 2>&1 | tail -3
echo "==> 完成: $APP"
