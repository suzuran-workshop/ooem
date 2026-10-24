#!/usr/bin/env bash
# 构建 + 安装到「应用程序」+ 后台启动（不弹终端窗口）
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh >/dev/null
DEST="/Applications/BetterDictation.app"
rm -rf "$DEST"
cp -R dist/BetterDictation.app "$DEST"
# open 会立刻脱离当前 shell，不占用终端
open "$DEST"
echo "已安装并启动：$DEST"
