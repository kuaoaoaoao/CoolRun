#!/usr/bin/env bash
# 全量类型检查（不需要 xcodebuild、不需要同意 Xcode license）
#
#   ./scripts/typecheck_stub.sh
#
# 做法：把源码复制到临时目录，把 PostHog（SPM 依赖）换成桩，再用 Xcode 自带的
# swiftc 做 -typecheck。比 `swiftc -parse` 强：能查类型、能查 MainActor 隔离。
#
# 两个必需的坑：
#   - `-Xfrontend -disable-sandbox`：不加的话宏插件会报
#     "swift-plugin-server produced malformed response"（SwiftUIMacros / ObservationMacros）。
#   - `-default-isolation MainActor`：与 target 的构建设置保持一致，否则会漏掉
#     真正的隔离警告。
#
# 测试 target 无法用这种方式编译（沙箱里 XCTest 的 clang module 加载不全，
# 报 "cannot find 'XCTAssertEqual' in scope"），跑单测仍需 xcodebuild。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SRC=$(pwd)
DST=${TMPDIR:-/tmp}/coolrun-typecheck

TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
SWIFTC="$TC/usr/bin/swiftc"
if [[ ! -x "$SWIFTC" || ! -d "$SDK" ]]; then
  echo "需要完整 Xcode（找不到 swiftc 或 macOS SDK）：$TC" >&2
  exit 2
fi

rm -rf "$DST"
mkdir -p "$DST"
cp -R "$SRC/CoolRun" "$DST/CoolRun" || exit 1

# PostHog 是 SPM 依赖，这里没有包解析结果，换成桩。
python3 - "$DST/CoolRun/Core/Analytics.swift" <<'PY'
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
src = src.replace("import PostHog\n", "")
src = re.sub(
    r"static func configure\(projectToken: String, host: String, enabled: Bool\) \{.*?\n    \}",
    "static func configure(projectToken: String, host: String, enabled: Bool) {\n"
    "        _ = (projectToken, host, enabled)\n    }",
    src, count=1, flags=re.S,
)
src = re.sub(
    r"static func makePostHogConfiguration\(.*?\n    \}",
    "static func makePostHogConfiguration(_ projectToken: String, host: String) -> [String: Any] {\n"
    '        ["token": projectToken, "host": host]\n    }',
    src, count=1, flags=re.S,
)
src = re.sub(r"PostHogSDK\.shared\.\w+\([^)]*\)", "()", src)
src = re.sub(r"PostHogSDK\.shared\.\w+", "()", src)
# 桩掉调用后可能残留 `())`，语法上非法。
src = src.replace("        ())\n    }", "        _ = ()\n    }")
open(path, "w", encoding="utf-8").write(src)
PY

cd "$DST" || exit 1
LOG="$DST/typecheck.log"
find CoolRun -name '*.swift' -print0 | xargs -0 "$SWIFTC" -typecheck \
  -swift-version 5 \
  -default-isolation MainActor \
  -target arm64-apple-macos15.0 \
  -module-cache-path "$DST/mc" \
  -sdk "$SDK" \
  -Xfrontend -disable-sandbox >"$LOG" 2>&1

# 只数诊断主行（`path:line:col: warning: ...`），别把续行的说明也算进去。
errors=$(grep -cE "^[^ ].*: error:" "$LOG")
warnings=$(grep -cE "^[^ ].*: warning:" "$LOG")
echo "error: $errors    warning: $warnings"

if [[ "$errors" -gt 0 ]]; then
  grep -E "^[^ ].*: error:" "$LOG" | head -40
  exit 1
fi
if [[ "$warnings" -gt 0 ]]; then
  # 基线只有一条 ToolRegistry.swift 的既有警告，多出来的都该修。
  grep -E "^[^ ].*: warning:" "$LOG" | sed "s|$DST/||" | head -20
fi
exit 0
