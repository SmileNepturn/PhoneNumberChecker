# HTTPS 배포 방법

이 앱은 정적 파일만으로 동작하므로 GitHub Pages 같은 HTTPS 정적 호스팅에 올릴 수 있습니다. DB와 전화번호 매칭은 서버가 아니라 사용자 아이폰 내부 IndexedDB에서 처리됩니다.

## GitHub Pages 배포

1. GitHub에서 새 저장소를 만듭니다.
2. 이 프로젝트를 해당 저장소에 push합니다.
3. GitHub 저장소의 `Settings > Pages`로 이동합니다.
4. `Build and deployment`의 `Source`를 `GitHub Actions`로 선택합니다.
5. `main` 브랜치에 push하면 `.github/workflows/pages.yml`이 자동 배포합니다.
6. 배포가 끝나면 Actions 화면 또는 Pages 설정에서 HTTPS 주소를 확인합니다.

## 아이폰 설치

1. 아이폰 Safari에서 GitHub Pages HTTPS 주소를 엽니다.
2. 공유 버튼을 누릅니다.
3. `홈 화면에 추가`를 선택합니다.
4. 홈 화면의 `전화 DB` 아이콘으로 실행합니다.
5. 최초 실행 후 OCR 파일 캐시가 끝나면 앱 파일과 OCR 데이터가 아이폰에 저장됩니다.

## 운영 방식

- 사진 이미지는 DB에 저장하지 않습니다.
- 업체명, 전화번호, 주소, 통화 상태, 날짜만 아이폰 내부 DB에 저장합니다.
- `승락`, `거절`은 다음 OCR 매칭 때 숨깁니다.
- `부재중`은 다음 OCR 매칭 때 다시 보여줍니다.

## 주의

OCR 번들이 약 46MB라서 최초 설치 시 네트워크 상태에 따라 시간이 걸릴 수 있습니다. 앱 업데이트를 배포한 뒤 아이폰에서 예전 화면이 보이면 앱을 완전히 종료한 뒤 다시 열어 캐시를 갱신합니다.
