# Xcode 전달 전 점검

이 문서는 Xcode로 아이폰에 설치하기 직전 확인할 항목입니다.

## 현재 준비 완료된 항목

- SwiftUI iOS 앱 프로젝트 생성
- Xcode project 파일 생성
- 공유 Scheme 생성
- 카메라/사진 권한 문구 추가
- Apple Vision OCR 서비스 추가
- 빨간 볼펜 제거 전처리 추가
- 4방향 회전 후보 자동 선택 추가
- OCR bounding box 기반 행/열 복원 추가
- 아이폰 내부 JSON DB 저장소 추가
- `부재중`, `거절`, `승락` 검토 흐름 추가
- `거절`, `승락`은 다음 매칭에서 숨기고 `부재중`은 다시 표시
- DB 초기화 기능 추가

## Xcode에서 해야 할 일

1. `PhoneNumberCheckerIOS/PhoneNumberCheckerIOS.xcodeproj`를 연다.
2. 왼쪽 프로젝트 선택 후 `PhoneNumberCheckerIOS` target을 선택한다.
3. `Signing & Capabilities`에서 본인 Apple ID Team을 선택한다.
4. Bundle Identifier가 중복되면 `com.smilenepturn.PhoneNumberChecker` 뒤에 본인 식별자를 붙인다.
5. 아이폰을 연결하고 상단 기기 선택에서 본인 아이폰을 선택한다.
6. Run을 누른다.

## 터미널 사전 점검

Xcode가 설치된 Mac에서는 아래 명령으로 프로젝트 상태를 확인할 수 있습니다.

```bash
cd "/Users/songsfamily/Documents/New project/PhoneNumberCheckerIOS"
./preflight_ios.sh
```

현재 프로젝트는 Xcode 26.5 / iOS 26.5 SDK에서 시뮬레이터 빌드까지 확인했습니다. 실제 아이폰 설치 전에는 Xcode의 `Signing & Capabilities`에서 Apple ID Team을 선택해야 합니다.
