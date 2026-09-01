#!/bin/zsh
# 周预测任务测试 harness：手动编译 app 模块 + 指定测试文件为 xctest bundle 并运行。
# 用法: .zcode/run-weekly-tests.sh <测试文件...>（相对 CoolRunTests/ 的文件名）
# 背景：xcodebuild 的 SPM 沙箱在当前终端环境不可用（sandbox-exec: Operation not permitted），
# 因此用 swiftc 手动构建；PostHog 对象复用 Xcode GUI 的 DerivedData 产物。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED=/Users/kuao/Library/Developer/Xcode/DerivedData/CoolRun-fxhsucdwupwsyjfyxujevgdlanwx/Build/Products/Debug
OUT="$ROOT/.zcode/testrun"
FW=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
XCLIB=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib
XCSC=/Applications/Xcode.app/Contents/Developer
mkdir -p "$OUT/GoldTests.xctest/Contents/MacOS"

if [ ! -f "$OUT/GoldTests.xctest/Contents/Info.plist" ]; then
  cat > "$OUT/GoldTests.xctest/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>GoldTests</string>
	<key>CFBundleIdentifier</key><string>org.coolrun.goldtests</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>GoldTests</string>
	<key>CFBundlePackageType</key><string>BNDL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
EOF
fi

cd "$ROOT/CoolRun"
NEWEST_APP=$(ls -t *.swift | head -1)
if [ ! -f "$OUT/app.o" ] || [ "$NEWEST_APP" -nt "$OUT/app.o" ] || [ ! -f "$OUT/CoolRun.swiftmodule" ] || [ "$NEWEST_APP" -nt "$OUT/CoolRun.swiftmodule" ]; then
  echo "== compiling app module =="
  swiftc -module-name CoolRun -swift-version 5 -default-isolation MainActor -D DEBUG \
    -target arm64-apple-macos15.0 -enable-testing -suppress-warnings \
    -I "$DERIVED" -emit-module -o "$OUT/CoolRun.swiftmodule" \
    $(ls *.swift | grep -v CoolRunApp.swift) || exit 1
  swiftc -module-name CoolRun -swift-version 5 -default-isolation MainActor -D DEBUG \
    -target arm64-apple-macos15.0 -enable-testing -suppress-warnings \
    -I "$DERIVED" -c -force-single-frontend-invocation -o "$OUT/app.o" \
    $(ls *.swift | grep -v CoolRunApp.swift) || exit 1
fi

cd "$ROOT/CoolRunTests"
echo "== compiling tests =="
env DEVELOPER_DIR=$XCSC xcrun swiftc -swift-version 5 -default-isolation MainActor -D DEBUG \
  -target arm64-apple-macos15.0 -enable-testing -suppress-warnings \
  -I "$OUT" -I "$DERIVED" -I "$XCLIB" -F "$FW" -c -force-single-frontend-invocation -o "$OUT/tests.o" \
  "$@" || exit 1

echo "== linking =="
env DEVELOPER_DIR=$XCSC xcrun swiftc \
  "$OUT/tests.o" "$OUT/app.o" \
  "$DERIVED/PostHog.o" "$DERIVED/PHPLCrashReporter.o" "$DERIVED/phlibwebp.o" "$ROOT/.zcode/posthog_stub.c" \
  -F "$FW" -L "$XCLIB" \
  -Xlinker -bundle \
  -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$XCLIB" \
  -framework XCTest -framework Cocoa -framework SwiftUI \
  -target arm64-apple-macos15.0 \
  -o "$OUT/GoldTests.xctest/Contents/MacOS/GoldTests" || exit 1

echo "== bundling resources =="
mkdir -p "$OUT/GoldTests.xctest/Contents/Resources"
cp "$ROOT"/CoolRun/*.json "$OUT/GoldTests.xctest/Contents/Resources/" 2>/dev/null || true

echo "== running =="
env DEVELOPER_DIR=$XCSC "$XCSC/usr/bin/xctest" "$OUT/GoldTests.xctest" 2>&1 | grep -vE "Failed to save|NSCocoaErrorDomain|NSFilePath|NSURL=|NSUnderlyingError"
EXIT=${pipestatus[1]}
echo "XCTEST_EXIT=$EXIT"
exit $EXIT
