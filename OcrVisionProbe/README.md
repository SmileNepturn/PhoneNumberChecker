# OcrVisionProbe

Vision OCR로 표 사진에서 `업체명 / 전화번호 / 업종` 행을 추출하는 검증용 CLI입니다.

## 실행

```bash
cd OcrVisionProbe
swift run ocr-vision-probe /path/to/sample.jpg
```

기본값은 `--orientation auto`이며, `up/right/left/down` 네 방향을 모두 OCR한 뒤 전화번호가 가장 많이 잡히는 결과를 선택합니다.

원본 OCR 좌표까지 확인하려면:

```bash
swift run ocr-vision-probe /path/to/sample.jpg --raw
```

## sample.JPG 검증

```bash
cd OcrVisionProbe
swift run ocr-vision-probe /Users/songsfamily/Desktop/sample.JPG
```

현재 샘플에서는 32개 행을 추출합니다. 사용자 정답지의 전화번호와 비교하면 28/32건이 일치합니다.

확인된 한계:

- OCR 엔진이 글자를 다르게 읽으면 파서가 정답으로 보정할 수 없습니다. 예: `디자인퓨어`와 `디자인문어`.
- 빨간 펜이 숫자를 지나간 행은 Vision이 숫자를 잘못 읽을 수 있습니다. 현재 샘플의 불일치 번호는 `042-482-2082`, `042-485-4747`, `042-523-9073`, `0507-1454-8584`입니다.
- 이 문제는 파서 문제가 아니라 OCR 인식값 차이입니다.

## iPhone 앱 적용 흐름

이 CLI의 핵심 로직은 iOS 앱에서도 그대로 사용할 수 있습니다.

1. `VNDocumentCameraViewController` 또는 사진 선택으로 `UIImage` 획득
2. `VNRecognizeTextRequest` 실행
3. `VNRecognizedTextObservation.boundingBox`를 `OCRItem`으로 변환
4. `parseRecords(from:)`와 같은 방식으로 행 묶기
5. 화면에서 사용자가 결과를 검수하고 수정
