# 전화번호 OCR DB PWA

아이폰에서 사진을 찍어 한국 업체 전화번호를 OCR로 추출하고, 전화번호 기준으로 중복을 제외해 로컬 DB에 저장하는 PWA입니다.

## 실행

```bash
python3 -m http.server 4173
```

브라우저에서 `http://localhost:4173`으로 접속합니다.

아이폰에서 사용하려면 같은 네트워크에서 접속 가능한 주소로 열고 Safari의 `공유 > 홈 화면에 추가`를 선택합니다.

## 아이폰 단독 실행 방식

이 앱은 OCR 실행 파일과 한국어/영어 학습 데이터를 `vendor/` 안에 포함합니다. 홈 화면에 추가한 뒤 앱 파일 캐시가 완료되면, 맥 서버는 설치와 업데이트를 제공하는 역할만 하고 실제 DB와 매칭은 아이폰 안에서 처리됩니다.

단, iOS에서 안정적인 오프라인 PWA 설치와 서비스 워커 캐시는 HTTPS 환경이 가장 안전합니다. 맥의 임시 `http.server`는 개발 테스트용이며, 실사용 설치는 HTTPS 호스팅이나 로컬 HTTPS 서버로 진행하는 것이 좋습니다.

HTTPS 배포는 [DEPLOYMENT.md](./DEPLOYMENT.md)를 따릅니다.

## 주요 기능

- 아이폰 카메라 촬영 또는 사진 보관함 이미지 선택
- 이미지 미리보기에서 시계방향/반시계방향 90도 회전 후 수동 추출
- 기본 ROI 영역을 꼭지점으로 조정한 뒤 해당 영역만 추출
- 로컬 Tesseract.js 기반 한글/영문 OCR
- OCR 전 이미지 확대, 회색조, 대비 강화, 이진화 전처리
- 한국 전화번호 추출 및 정규화
- IndexedDB 로컬 저장
- 촬영 이미지는 OCR 직후 폐기하고 DB에 저장하지 않음
- 기존 전화번호 중복 제외
- 전화번호 추출 실패 시 재촬영 안내
- `부재중`, `거절`, `승락` 상태 저장
- 다음 OCR 매칭 때 `거절`, `승락`은 숨기고 `부재중`은 다시 표시
- 업체명, 전화번호, 주소 저장 전 수정
- 이력 검색과 CSV 내보내기
- 테스트/운영 초기화를 위한 DB 초기화

## OCR 정확도 검증

브라우저 PWA의 Tesseract.js OCR은 표 사진과 빨간 볼펜 표시가 섞인 샘플에서 정확도가 낮았습니다. 같은 이미지에서 Apple Vision OCR은 좌표 기반 행 복원으로 32개 행을 추출했습니다.

검증용 Swift CLI는 `OcrVisionProbe/`에 포함되어 있습니다.

```bash
cd OcrVisionProbe
swift run ocr-vision-probe /Users/songsfamily/Desktop/sample.JPG
```

이 로직은 최종 iPhone 네이티브 앱으로 옮길 기준 구현입니다. PWA는 배포와 UI 검증용으로 유지하고, 실사용 OCR은 Vision 기반 네이티브 구현이 맞습니다.

## iPhone 네이티브 앱

아이폰 단독 실행용 SwiftUI 앱은 `PhoneNumberCheckerIOS/`에 추가되어 있습니다. Apple Vision OCR과 아이폰 내부 JSON DB를 사용하므로 설치 후에는 Mac 서버나 GitHub Pages 없이 OCR, 매칭, 검토, 저장이 모두 아이폰 안에서 처리됩니다.

## 파일 구성

- `index.html`: 앱 화면 구조
- `styles.css`: 모바일 중심 UI 스타일
- `src/app.js`: OCR, 전화번호 추출, IndexedDB, 검토 플로우
- `manifest.webmanifest`: 홈 화면 추가용 PWA 설정
- `service-worker.js`: 앱 정적 파일 캐시
- `DEVELOPMENT_PLAN.md`: 개발 계획
- `OcrVisionProbe/`: Apple Vision OCR 좌표 기반 추출 검증 CLI
- `PhoneNumberCheckerIOS/`: 아이폰 단독 실행용 SwiftUI + Vision OCR 앱
- `vendor/tesseract/`: 오프라인 OCR 실행 파일
- `vendor/tessdata/`: 오프라인 OCR 언어 데이터

## 카메라 동작

`사진찍기`는 iPhone에서 잘 동작했던 `capture` 입력 방식으로 카메라 촬영을 엽니다. `이미지 선택`은 `capture` 없이 사진 보관함/파일 선택을 엽니다. 이미지를 불러온 뒤 미리보기에서 방향을 맞추고 `추출`을 누르면 OCR을 실행합니다.
