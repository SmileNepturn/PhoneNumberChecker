# 아이폰 설치 직전 절차

현재 저장소에는 아이폰 단독 실행 앱이 준비되어 있습니다. Mac에 Xcode가 설치되어 있고 아이폰이 연결되어 있으면 아래 순서로 설치할 수 있습니다.

## 1. 프로젝트 열기

Finder에서 아래 파일을 더블클릭합니다.

```text
PhoneNumberCheckerIOS/open_in_xcode.command
```

또는 Xcode에서 직접 아래 프로젝트를 엽니다.

```text
PhoneNumberCheckerIOS/PhoneNumberCheckerIOS.xcodeproj
```

## 2. Xcode 최초 설정

1. Xcode 왼쪽에서 프로젝트 `PhoneNumberCheckerIOS`를 선택합니다.
2. Target `PhoneNumberCheckerIOS`를 선택합니다.
3. `Signing & Capabilities`로 이동합니다.
4. `Team`에서 본인 Apple ID 팀을 선택합니다.
5. Bundle Identifier 오류가 뜨면 `com.smilenepturn.PhoneNumberChecker` 뒤에 본인 이름이나 숫자를 붙입니다.

예:

```text
com.smilenepturn.PhoneNumberChecker.songsfamily
```

## 3. 아이폰 연결

1. 아이폰을 USB로 연결합니다.
2. 아이폰에서 `이 컴퓨터를 신뢰`를 누릅니다.
3. Xcode 상단 기기 목록에서 본인 아이폰을 선택합니다.
4. Run 버튼을 누릅니다.

## 4. 아이폰에서 처음 실행

1. 앱이 설치되면 실행합니다.
2. 카메라 권한을 허용합니다.
3. 사진 보관함 권한을 허용합니다.
4. `사진찍기` 또는 `이미지 선택`으로 표 이미지를 넣고 `추출`을 누릅니다.

## 5. 설치 후 동작 방식

- Mac 서버는 필요 없습니다.
- GitHub Pages도 필요 없습니다.
- 이미지는 저장하지 않습니다.
- 전화번호 DB는 아이폰 앱 내부에 저장됩니다.
- `거절`, `승락`은 다음 OCR 매칭 때 숨겨집니다.
- `부재중`은 다시 전화해야 하므로 다음 OCR 매칭 때 다시 표시됩니다.
