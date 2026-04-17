# muxbar Distribution

## 릴리스 절차

1. 버전 확정 (semver) → `./Release.sh 0.1.0`
2. `dist/muxbar-0.1.0.dmg` 생성됨
3. GitHub Release 생성 → .dmg 업로드
4. SHA256 복사 → `HomebrewTap/muxbar.rb` 의 `sha256` 업데이트
5. `1989v/homebrew-tap` 별도 레포에 `Casks/muxbar.rb` 푸시

## 전제 조건

- Xcode 설치 (codesign, universal binary 빌드)
- `brew install create-dmg` (dmg 패키징)
- 사용자 검증: `brew install --cask 1989v/tap/muxbar`

## Ad-hoc 서명의 한계

Apple Developer 계정 없음 → notarize 불가. 사용자는 첫 실행 시 우클릭 → 열기 필요.
Homebrew cask 가 `xattr -dr com.apple.quarantine` 로 자동 우회.
