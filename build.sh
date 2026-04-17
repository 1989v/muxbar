#!/bin/bash
# muxbar .app 번들 생성 스크립트 — Xcode 불필요 (CommandLineTools + Swift 툴체인만)
#
# 사용:
#   ./build.sh              # Release 빌드 + .app 생성 + ad-hoc codesign
#   ./build.sh install      # 위에 추가로 /Applications/muxbar.app 로 복사
#   ./build.sh open         # 위에 추가로 실행
#
# 산출물: ./muxbar.app

set -euo pipefail

VERSION="${VERSION:-0.1.0-dev}"
BUNDLE_ID="com.1989v.muxbar"
APP_NAME="muxbar.app"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$REPO_ROOT/$APP_NAME"

SUBCMD="${1:-}"

echo "[1/5] 전제 조건 확인"
if ! command -v swift >/dev/null 2>&1; then
    echo "  ✗ swift 미설치. xcode-select --install 실행" && exit 1
fi
if ! command -v codesign >/dev/null 2>&1; then
    echo "  ✗ codesign 미설치. xcode-select --install 실행" && exit 1
fi
echo "  ✓ swift $(swift --version 2>&1 | head -1 | grep -oE 'version [0-9.]+')"
echo "  ✓ codesign"

echo "[2/5] swift build -c release"
cd "$REPO_ROOT"
swift build -c release 2>&1 | tail -3
BINARY_PATH="$REPO_ROOT/.build/release/muxbar"
if [ ! -f "$BINARY_PATH" ]; then
    echo "  ✗ 빌드 실패: $BINARY_PATH 없음" && exit 1
fi

echo "[3/5] .app 번들 디렉터리 생성"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/muxbar"
chmod +x "$APP_PATH/Contents/MacOS/muxbar"

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>muxbar</string>
    <key>CFBundleDisplayName</key><string>muxbar</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key><string>muxbar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 kgd. MIT.</string>
</dict>
</plist>
EOF

echo "[4/5] Ad-hoc codesign (무서명 대신 최소 무결성)"
codesign --deep --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH" 2>&1 && echo "  ✓ 서명 검증 통과"

# Gatekeeper quarantine 제거 (현재 빌드 머신에서 바로 실행 가능하게)
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "[5/5] 완료: $APP_PATH"

case "$SUBCMD" in
    install)
        echo "→ /Applications 에 설치"
        rm -rf "/Applications/$APP_NAME"
        cp -R "$APP_PATH" "/Applications/$APP_NAME"
        echo "  ✓ /Applications/$APP_NAME"
        ;;
    open)
        echo "→ 실행"
        pkill -f muxbar 2>/dev/null || true
        sleep 1
        open "$APP_PATH"
        ;;
    "")
        echo ""
        echo "실행: open $APP_PATH"
        echo "또는: ./build.sh open"
        ;;
    *)
        echo "알 수 없는 서브커맨드: $SUBCMD (사용 가능: install / open)"
        exit 1
        ;;
esac
