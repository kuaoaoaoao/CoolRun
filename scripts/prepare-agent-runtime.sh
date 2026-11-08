#!/bin/bash
#
# prepare-agent-runtime.sh
# 把 DeepSeek Harness 的单文件运行时下载下来，塞进 CoolRun.app。
#
# 用法:
#   ./scripts/prepare-agent-runtime.sh /path/to/CoolRun.app
#
# 环境变量:
#   DSH_RUNTIME_VERSION  指定版本，默认取 PyPI 上最新的稳定版
#   COOLRUN_RUNTIME_CACHE  缓存目录，默认 .build/AgentRuntime
#
# 只在打「完整版」时调用。轻量版不带这个运行时，装好后按需下载。

set -euo pipefail

APP_PATH="${1:?用法: $0 /path/to/CoolRun.app}"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ 找不到 $APP_PATH"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${COOLRUN_RUNTIME_CACHE:-$ROOT/.build/AgentRuntime}"
VERSION="${DSH_RUNTIME_VERSION:-}"
PKG_NAME="deepseek-harness-runtime-bin"

mkdir -p "$CACHE"

# --- 1. 确定版本与下载地址 ------------------------------------------------

if [ -z "$VERSION" ]; then
  echo "🔎 查询 PyPI 上的最新版本…"
  VERSION=$(curl -fsSL "https://pypi.org/pypi/$PKG_NAME/json" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"])')
fi
echo "📌 运行时版本: $VERSION"

WHEEL="$CACHE/$PKG_NAME-$VERSION.whl"

if [ ! -f "$WHEEL" ]; then
  echo "⬇️  下载 wheel（约 90 MB）…"
  URL=$(curl -fsSL "https://pypi.org/pypi/$PKG_NAME/$VERSION/json" \
    | python3 -c '
import json, sys
data = json.load(sys.stdin)
want = sys.argv[1]
for entry in data["urls"]:
    if "macosx" in entry["filename"] and "arm64" in entry["filename"]:
        print(entry["url"])
        break
' "$PKG_NAME")
  if [ -z "$URL" ]; then
    echo "❌ 这个版本没有 arm64 macOS 的 wheel"
    exit 1
  fi
  curl -fL --progress-bar -o "$WHEEL" "$URL"
else
  echo "✅ 复用缓存: $WHEEL"
fi

# --- 2. 解包 --------------------------------------------------------------

if [ ! -x "$CACHE/deepseek-harness-sdk-runtime" ]; then
  echo "📦 解包…"
  unzip -oq "$WHEEL" -d "$CACHE/unpacked"
  # wheel 里的文件名带平台后缀，例如 deepseek-harness-sdk-runtime-macos-arm64，
  # 而 app 里认的是无后缀的 deepseek-harness-sdk-runtime，所以要挑出主程序改名。
  RUNTIME=$(find "$CACHE/unpacked" -name "deepseek-harness-sdk-runtime*" -type f \
    | grep -v -- '-rg$' | grep -v -- '-spawn-helper$' | head -1)
  if [ -z "$RUNTIME" ]; then
    echo "❌ 解包后找不到运行时可执行文件"
    exit 1
  fi
  RUNTIME_DIR="$(dirname "$RUNTIME")"
  cp "$RUNTIME" "$CACHE/deepseek-harness-sdk-runtime"
  # sidecar 保持带后缀的名字，dsh 会自己在同目录找。
  for f in "$RUNTIME_DIR"/deepseek-harness-sdk-runtime*; do
    case "$(basename "$f")" in
      *-rg) cp "$f" "$CACHE/deepseek-harness-sdk-runtime-rg" ;;
      *-spawn-helper) cp "$f" "$CACHE/deepseek-harness-sdk-runtime-spawn-helper" ;;
    esac
  done
  chmod +x "$CACHE"/deepseek-harness-sdk-runtime*
fi

if [ ! -x "$CACHE/deepseek-harness-sdk-runtime" ]; then
  echo "❌ 缓存里没有可用的运行时"
  exit 1
fi

# --- 3. 拷进 app ----------------------------------------------------------

DEST="$APP_PATH/Contents/Resources/AgentRuntime"
echo "🚚 复制到 $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$CACHE"/deepseek-harness-sdk-runtime* "$DEST/"
chmod +x "$DEST"/deepseek-harness-sdk-runtime*

echo "🔏 重新做 ad-hoc 签名"
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || \
  echo "⚠️  签名失败（不影响本地运行，但分发前需要处理）"

SIZE=$(du -sh "$DEST" | cut -f1)
echo "✅ 完整版就绪，运行时占用 $SIZE"
