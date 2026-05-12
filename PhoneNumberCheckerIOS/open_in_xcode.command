#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT_DIR/PhoneNumberCheckerIOS.xcodeproj"

if [ ! -d "/Applications/Xcode.app" ]; then
  echo "Xcode가 /Applications/Xcode.app에 없습니다."
  echo "App Store에서 Xcode를 설치한 뒤 다시 실행하세요."
  read -r "?Enter를 누르면 닫습니다."
  exit 1
fi

open -a Xcode "$PROJECT"
