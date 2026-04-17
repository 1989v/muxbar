#!/bin/bash
# muxbar 릴리스 빌드 + .dmg 패키징
# 실행 전제: Xcode 설치 + DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

set -euo pipefail

VERSION="${1:-0.1.0}"
OUT_DIR="dist"
APP_NAME="muxbar.app"

echo "[1/5] swift build -c release (universal)"
swift build -c release --arch arm64 --arch x86_64

echo "[2/5] .app 번들 생성"
mkdir -p "$OUT_DIR/$APP_NAME/Contents/MacOS"
mkdir -p "$OUT_DIR/$APP_NAME/Contents/Resources"

cp .build/apple/Products/Release/muxbar "$OUT_DIR/$APP_NAME/Contents/MacOS/muxbar"

cat > "$OUT_DIR/$APP_NAME/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>muxbar</string>
<key>CFBundleDisplayName</key><string>muxbar</string>
<key>CFBundleIdentifier</key><string>com.1989v.muxbar</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleExecutable</key><string>muxbar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

echo "[3/5] Ad-hoc codesign"
codesign --deep --force --sign - "$OUT_DIR/$APP_NAME"

echo "[4/5] create-dmg"
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg 없음. brew install create-dmg"
    exit 1
fi
create-dmg \
    --volname "muxbar $VERSION" \
    --app-drop-link 450 120 \
    "$OUT_DIR/muxbar-$VERSION.dmg" \
    "$OUT_DIR/$APP_NAME"

echo "[5/5] SHA256"
shasum -a 256 "$OUT_DIR/muxbar-$VERSION.dmg"

echo "done → $OUT_DIR/muxbar-$VERSION.dmg"
