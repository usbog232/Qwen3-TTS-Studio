#!/bin/bash
# 构建 Qwen3-TTS Studio.app
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

BIN=$(swift build -c release --show-bin-path)/Qwen3TTSStudio
APPDIR=build/Qwen3-TTS-Studio.app
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"

# Info.plist
cat > "$APPDIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Qwen3-TTS Studio</string>
    <key>CFBundleDisplayName</key><string>Qwen3-TTS Studio</string>
    <key>CFBundleIdentifier</key><string>local.qwen3tts.studio</string>
    <key>CFBundleVersion</key><string>1.1.0</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleExecutable</key><string>Qwen3TTSStudio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>用于录制参考人声，让 Qwen3-TTS 用这个声音朗读你的文字。</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

cp "$BIN" "$APPDIR/Contents/MacOS/Qwen3TTSStudio"
codesign --force --deep -s - "$APPDIR" 2>/dev/null || true

echo "==> done: $APPDIR"
ls -lh "$APPDIR/Contents/MacOS/Qwen3TTSStudio"
