#!/usr/bin/env bash
# 从 Swift 源码提取版本号（单一来源：AppVersion.marketing）
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/.*public static let marketing = "\([^"]*\)".*/\1/p' \
  Sources/BetterDictationCore/Support/AppVersion.swift | head -1)

if [ -z "$version" ]; then
  echo "无法从 AppVersion.swift 解析版本号" >&2
  exit 1
fi
printf '%s\n' "$version"
