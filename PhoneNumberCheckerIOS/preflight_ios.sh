#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT_DIR/PhoneNumberCheckerIOS.xcodeproj"
PLIST="$ROOT_DIR/PhoneNumberCheckerIOS/Info.plist"
SCHEME="PhoneNumberCheckerIOS"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

export DEVELOPER_DIR

echo "1. Info.plist 확인"
plutil -lint "$PLIST"

echo "2. Xcode project 확인"
plutil -lint "$PROJECT/project.pbxproj"

echo "3. Xcode CLI 상태 확인"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode CLI가 아직 준비되지 않았습니다."
  echo "Xcode 설치와 iOS SDK 설치가 끝났는지 확인하세요."
  exit 0
fi

echo "4. Scheme 확인"
xcodebuild -list -project "$PROJECT"

echo "5. 시뮬레이터 빌드 확인"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  build
