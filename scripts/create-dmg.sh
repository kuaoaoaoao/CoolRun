#!/bin/bash
#
# create-dmg.sh
# 从 Xcode 导出的 CoolRun.app 制作 DMG 安装包
#
# 用法:
#   ./scripts/create-dmg.sh                      # 轻量版，自动找最新构建产物
#   ./scripts/create-dmg.sh --full               # 完整版，内置 Agent 运行时
#   ./scripts/create-dmg.sh --full /path/to/CoolRun.app
#
# 轻量版约 8 MB，Agent 运行时按需下载。
# 完整版约 100 MB，装好即用，断网也能跑。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

EDITION="lite"
APP_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --full) EDITION="full"; shift ;;
    --lite) EDITION="lite"; shift ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "❌ 未知参数: $1"
      exit 1
      ;;
    *)
      APP_PATH="$1"
      shift
      ;;
  esac
done

# 查找最新的 Xcode 构建产物
find_latest_app() {
  # 先看刚构建出来的产物：导出的时间戳目录往往是旧版本，优先用 Release。
  local built="$SCRIPT_DIR/.build/DerivedData/Build/Products/Release/CoolRun.app"
  if [ -d "$built" ]; then
    echo "$built"
    return
  fi
  local latest_dir
  latest_dir=$(ls -dt "$SCRIPT_DIR"/CoolRun\ 2* 2>/dev/null | head -1 || true)
  if [ -n "$latest_dir" ] && [ -d "$latest_dir/CoolRun.app" ]; then
    echo "$latest_dir/CoolRun.app"
  fi
}

if [ -z "$APP_PATH" ]; then
  APP_PATH=$(find_latest_app)
  if [ -z "$APP_PATH" ]; then
    echo "❌ 找不到构建产物"
    echo "用法: $0 [--full|--lite] /path/to/CoolRun.app"
    echo "或在 Xcode 构建后直接运行 $0"
    exit 1
  fi
  echo "🔍 自动找到: $APP_PATH"
fi

if [ ! -d "$APP_PATH" ]; then
  echo "❌ 找不到 $APP_PATH"
  exit 1
fi

if [ "$EDITION" = "full" ]; then
  VOLUME_NAME="CoolRun"
  DMG_NAME="CoolRun-Full.dmg"
else
  VOLUME_NAME="CoolRun Lite"
  DMG_NAME="CoolRun-Lite.dmg"
fi

DMG_DIR=$(mktemp -d)
trap 'rm -rf "$DMG_DIR"' EXIT

echo "📦 正在制作 $EDITION DMG..."

APP_NAME="CoolRun.app"
cp -R "$APP_PATH" "$DMG_DIR/$APP_NAME"

# 运行时只注入到 dmg 里的副本，不动构建产物 —— 否则先打 full 再打 lite，
# lite 会把上一次残留的 300 MB 运行时一起带进去。
if [ "$EDITION" = "full" ]; then
  echo "🧩 准备内置 Agent 运行时…"
  "$SCRIPT_DIR/scripts/prepare-agent-runtime.sh" "$DMG_DIR/$APP_NAME"
else
  rm -rf "$DMG_DIR/$APP_NAME/Contents/Resources/AgentRuntime"
  codesign --force --deep --sign - "$DMG_DIR/$APP_NAME" 2>/dev/null || true
fi

ln -s /Applications "$DMG_DIR/Applications"

rm -f "$SCRIPT_DIR/$DMG_NAME"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -format UDZO \
  "$SCRIPT_DIR/$DMG_NAME"

SIZE=$(du -sh "$SCRIPT_DIR/$DMG_NAME" | cut -f1)
echo "✅ 已生成: $SCRIPT_DIR/$DMG_NAME ($SIZE)"
