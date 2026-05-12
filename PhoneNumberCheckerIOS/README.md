# PhoneNumberChecker iOS

아이폰 단독 실행용 SwiftUI 앱입니다. 웹/PWA와 달리 서버가 필요 없고, Apple Vision OCR과 앱 내부 JSON DB를 사용합니다.

## 기능

- 카메라 촬영 또는 사진 보관함 이미지 선택
- Apple Vision OCR `ko-KR`, `en-US` 인식
- 4방향 이미지 회전 후보 자동 테스트
- 빨간 볼펜 영역 제거 후 OCR
- OCR bounding box 기반 행 묶기
- 전화번호 기준 업체명 / 업종 또는 주소 영역 분리
- `부재중`, `거절`, `승락` 저장
- 다음 이미지 추출 시 `거절`, `승락` 번호는 숨김
- `부재중` 번호는 다시 검토 대상으로 표시
- 이미지 파일은 저장하지 않고, 전화번호 DB만 아이폰 내부 Documents 폴더에 저장

## 아이폰에서 실행

1. Mac에 Xcode를 설치합니다.
2. 이 파일을 엽니다.

   ```text
   PhoneNumberCheckerIOS/PhoneNumberCheckerIOS.xcodeproj
   ```

3. Xcode 상단 대상 기기를 본인 아이폰으로 선택합니다.
4. `Signing & Capabilities`에서 본인 Apple ID Team을 선택합니다.
5. 아이폰을 USB로 연결하거나 같은 네트워크 무선 디버깅을 켠 뒤 Run을 누릅니다.

처음 실행하면 카메라와 사진 접근 권한을 허용해야 합니다.

## 현재 Mac CLI 상태

현재 이 작업 환경은 `xcodebuild`가 Xcode가 아닌 Command Line Tools를 보고 있어 터미널 빌드는 바로 되지 않습니다.

```text
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Xcode 설치 후 위 설정을 하면 터미널에서도 빌드 확인이 가능합니다.
