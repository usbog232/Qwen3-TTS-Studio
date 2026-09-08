#!/bin/bash
# 构建 xjtts.app（Qwen3-TTS 声音工作站）
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

BIN=$(swift build -c release --show-bin-path)/xjtts
APPDIR=build/xjtts.app
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"

# 图标：assets/icon.png -> xjtts.icns
ICONSET=build/xjtts.icon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
python3 - "$ICONSET" <<'EOF'
import subprocess, sys, os
src = "assets/icon.png"
out = sys.argv[1]
tmp = "/tmp/xjtts_1024.png"
subprocess.run(["sips","-z","1024","1024",src,"--out",tmp], check=True, capture_output=True)
specs = [(16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),
         (128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),
         (512,"icon_256x256@2x.png"),(512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")]
for px, name in specs:
    subprocess.run(["sips","-z",str(px),str(px),tmp,"--out",os.path.join(out,name)], check=True, capture_output=True)
EOF
iconutil -c icns "$ICONSET" -o "$APPDIR/Contents/Resources/xjtts.icns"

# Info.plist
cat > "$APPDIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>xjtts</string>
    <key>CFBundleDisplayName</key><string>xjtts</string>
    <key>CFBundleIdentifier</key><string>local.xjtts.app</string>
    <key>CFBundleVersion</key><string>1.2.0</string>
    <key>CFBundleShortVersionString</key><string>1.2.0</string>
    <key>CFBundleExecutable</key><string>xjtts</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>xjtts</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>用于录制参考人声，让 Qwen3-TTS 用这个声音朗读你的文字。</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

cp "$BIN" "$APPDIR/Contents/MacOS/xjtts"
codesign --force --deep -s - "$APPDIR" 2>/dev/null || true

echo "==> done: $APPDIR"
ls -lh "$APPDIR/Contents/MacOS/xjtts"
