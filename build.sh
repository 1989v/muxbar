#!/bin/bash
# muxbar .app 번들 생성 스크립트 — Xcode 불필요 (CommandLineTools + Swift 툴체인만)
#
# 사용:
#   ./build.sh              # Release 빌드 + ad-hoc codesign + /Applications/muxbar.app 교체
#   ./build.sh install      # 위와 같음 (예전 이름)
#   ./build.sh open         # 위에 추가로, 꺼져 있어도 실행
#
# 산출물: /Applications/muxbar.app 하나뿐. 조립은 .build/ 안에서 하고 옮긴다 —
# 레포에 .app 사본이 남으면 Spotlight·Launchpad 에 같은 앱이 여러 개 보인다.
# 실행 중이던 앱은 정상 종료 후 새 버전으로 다시 띄운다.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
# 버전은 git 에서 — 고정 문자열이면 최신 빌드가 옛 릴리스보다 낮은 버전으로 보인다.
VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
BUNDLE_ID="com.1989v.muxbar"
APP_NAME="muxbar.app"
APP_PATH="$REPO_ROOT/.build/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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

# SPM resource bundles (Bundle.module) 를 .app/Contents/Resources/ 로 복사.
# 누락 시 NSLocalizedString 의 lproj lookup 실패 → i18n 안 먹음.
shopt -s nullglob
for b in "$REPO_ROOT/.build/release/"*.bundle; do
    cp -R "$b" "$APP_PATH/Contents/Resources/"
done
shopt -u nullglob

# main bundle 에 .lproj 미러 — macOS 의 NSBundle.preferredLocalizations 가
# main bundle 의 가용 언어를 보고 결정하는 quirk 때문. SPM Bundle.module 만
# 있으면 main bundle 이 영어 only 로 인식돼 sub-bundle 의 ko lookup 도 fallback.
CORE_LPROJ="$APP_PATH/Contents/Resources/muxbar_Core.bundle"
if [ -d "$CORE_LPROJ" ]; then
    for lp in "$CORE_LPROJ"/*.lproj; do
        [ -d "$lp" ] || continue
        mkdir -p "$APP_PATH/Contents/Resources/$(basename "$lp")"
    done
fi

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>muxbar</string>
    <key>CFBundleDisplayName</key><string>muxbar</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key><string>muxbar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>© 2026 kgd. MIT.</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
    </array>
</dict>
</plist>
EOF

echo "[4/5] Ad-hoc codesign (무서명 대신 최소 무결성)"
codesign --deep --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH" 2>&1 && echo "  ✓ 서명 검증 통과"

# Gatekeeper quarantine 제거 (현재 빌드 머신에서 바로 실행 가능하게)
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "[5/5] 번들 완료"

case "$SUBCMD" in
    ""|install|open) ;;
    *)
        echo "알 수 없는 서브커맨드: $SUBCMD (사용 가능: install / open)"
        exit 1
        ;;
esac

echo "→ $INSTALL_PATH 교체"
# 앱 프로세스만 정확히 집는다. pkill -f muxbar 는 _muxbar-awake 같은 tmux 세션까지 맞는다.
APP_BIN="$INSTALL_PATH/Contents/MacOS/muxbar"
WAS_RUNNING=0
if pgrep -f "^$APP_BIN" >/dev/null; then
    WAS_RUNNING=1
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -f "^$APP_BIN" >/dev/null || break
        sleep 0.5
    done
    if pgrep -f "^$APP_BIN" >/dev/null; then
        echo "  ✗ 실행 중인 muxbar 가 종료되지 않음 — 직접 종료 후 다시 실행" && exit 1
    fi
fi
rm -rf "$INSTALL_PATH"
mv "$APP_PATH" "$INSTALL_PATH"
"$LSREGISTER" -f "$INSTALL_PATH" >/dev/null 2>&1 || true

# 예전 build.sh 가 레포에 남긴 사본 정리
if [ -d "$REPO_ROOT/$APP_NAME" ]; then
    "$LSREGISTER" -u "$REPO_ROOT/$APP_NAME" >/dev/null 2>&1 || true
    rm -rf "$REPO_ROOT/$APP_NAME"
fi
echo "  ✓ $INSTALL_PATH ($VERSION)"

if [ "$WAS_RUNNING" = 1 ] || [ "$SUBCMD" = open ]; then
    open "$INSTALL_PATH"
    echo "  ✓ 실행"
fi
