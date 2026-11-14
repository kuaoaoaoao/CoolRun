#!/usr/bin/env bash
#
# 项目自检。有 Xcode 时做真实编译；只有 CommandLineTools 时退化为语法解析。
#
# 用法：
#   ./scripts/verify.sh          # 编译 + 静态检查
#   ./scripts/verify.sh --test   # 额外跑单元测试
#
# 覆盖：
#   1. 全量编译（xcodebuild build，Debug 配置）
#   2. 顶层类型重名 / private 类型跨文件引用
#   3. switch 是否漏掉枚举新增的 case
#
# 有 Xcode 时第 2、3 项是冗余的（编译器自己会报），但它们的报错信息更聚焦，
# 拆分文件后能快速定位是哪个符号冲突；没有 Xcode 时则是唯一防线。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

RUN_TESTS=0
[ "${1:-}" = "--test" ] && RUN_TESTS=1

fail=0
step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# xcode-select 可能仍指向 CommandLineTools，此时用 DEVELOPER_DIR 显式指定 Xcode。
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

has_xcode=0
if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
    has_xcode=1
fi

if [ "$has_xcode" -eq 1 ]; then
    step "1/3 全量编译（$(xcodebuild -version | head -1)）"
    log=$(mktemp)
    if xcodebuild -project CoolRun.xcodeproj -scheme CoolRun \
        -configuration Debug -destination 'platform=macOS' build >"$log" 2>&1; then
        errors=$(grep -c 'error:' "$log" || true)
        warnings=$(grep -c 'warning:' "$log" || true)
        echo "OK: 编译通过（error=${errors}, warning=${warnings}）"
        if [ "$warnings" -gt 0 ]; then
            echo "--- 警告 ---"
            grep 'warning:' "$log" | sed 's|.*/CoolRun/|CoolRun/|' | sort -u | head -20
        fi
    else
        echo "FAIL: 编译失败"
        grep -E 'error:' "$log" | sed 's|.*/CoolRun/|CoolRun/|' | sort -u | head -40
        fail=1
    fi
    rm -f "$log"
else
    step "1/3 Swift 语法解析（未找到可用 Xcode，降级）"
    if command -v swiftc >/dev/null 2>&1; then
        if output=$(swiftc -parse $(find CoolRun -name '*.swift') 2>&1); then
            echo "OK: $(find CoolRun -name '*.swift' | wc -l | tr -d ' ') 个文件语法通过"
        else
            echo "$output" | head -40
            fail=1
        fi
    else
        echo "SKIP: 未找到 swiftc"
    fi
fi

step "2/3 类型可见性"
python3 scripts/check_visibility.py || fail=1

step "3/3 枚举 switch 完备性"
python3 scripts/check_enum_switches.py || fail=1

if [ "$RUN_TESTS" -eq 1 ]; then
    if [ "$has_xcode" -eq 1 ]; then
        step "附加 单元测试"
        log=$(mktemp)
        if xcodebuild -project CoolRun.xcodeproj -scheme CoolRun \
            -configuration Debug -destination 'platform=macOS' test >"$log" 2>&1; then
            echo "OK: $(grep -c 'Test case.*passed' "$log") 个用例通过"
        else
            echo "FAIL: 有测试未通过"
            # 三种失败长得不一样，都要报出来，否则只看到「有测试未通过」
            # 却不知道是哪个用例、还是测试代码压根没编译过。
            if grep -qE '(^| )error: ' "$log"; then
                echo "-- 编译错误 --"
                # 保留「文件:行:错误」的完整定位，只把工作目录前缀去掉。
                grep -E '(^| )error: ' "$log" | sed "s|$PWD/||" | sort -u | sed 's/^/  /' | head -20
            fi
            if grep -q 'Failing tests:' "$log"; then
                echo "-- 失败的用例 --"
                sed -n '/Failing tests:/,/^$/p' "$log" | grep -v 'Failing tests:' | sed 's/^[[:space:]]*/  /' | head -20
            fi
            if ! grep -qE '(^| )error: |Failing tests:' "$log"; then
                echo "-- 日志里既没有编译错误也没有失败用例，最后 20 行如下 --"
                tail -20 "$log" | sed 's/^/  /'
            fi
            kept="$PWD/.build/test-failure.log"
            mkdir -p "$(dirname "$kept")"
            cp "$log" "$kept"
            echo "完整日志：$kept"
            fail=1
        fi
        rm -f "$log"
    else
        step "附加 单元测试"
        echo "SKIP: 测试需要 xcodebuild"
    fi
fi

printf '\n'
if [ "$fail" -ne 0 ]; then
    echo "有检查未通过。"
    exit 1
fi
if [ "$has_xcode" -eq 1 ]; then
    echo "全部检查通过。"
else
    echo "静态检查通过（未做真实编译，请在 Xcode 中 ⌘B 确认）。"
fi
