#!/usr/bin/env bash
# 国际化改动验证：语法门 + 残留扫描
#
#   ./scripts/verify_i18n.sh           # 只查未本地化文案
#   ./scripts/verify_i18n.sh --parse   # 额外对全部 Swift 文件跑 swiftc -parse
#
# Xcode license 未同意时 xcodebuild 不可用，swiftc -parse 是唯一可用的语法门。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

status=0

echo "== 未本地化中文扫描 =="
python3 scripts/check_i18n.py || status=1

if [[ "${1:-}" == "--parse" ]]; then
  echo
  echo "== swiftc -parse 语法检查 =="
  while IFS= read -r -d '' file; do
    if ! out=$(swiftc -parse "$file" 2>&1); then
      echo "FAIL: $file"
      echo "$out" | head -5
      status=1
    fi
  done < <(find CoolRun -name '*.swift' -print0)
  echo "swiftc -parse 完成"
fi

exit $status
