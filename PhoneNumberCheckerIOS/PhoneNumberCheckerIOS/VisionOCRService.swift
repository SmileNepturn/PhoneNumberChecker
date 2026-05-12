import CoreGraphics
import Foundation
import ImageIO
import UIKit
import Vision

enum VisionOCRServiceError: LocalizedError {
    case missingCGImage
    case noText
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingCGImage:
            return "이미지를 OCR용 데이터로 변환하지 못했습니다."
        case .noText:
            return "전화번호를 찾지 못했습니다. 표 영역이 잘 보이도록 다시 촬영해주세요."
        case .failed(let message):
            return "OCR 실패: \(message)"
        }
    }
}

final class VisionOCRService {
    private let phonePattern = #"(?:0\d{1,3})[-\s.]?\d{3,4}[-\s.]?\d{4}|(?:1[568]\d{2})[-\s.]?\d{4}"#

    func recognizeRecords(from image: UIImage) async throws -> [OCRCandidate] {
        guard let originalCGImage = image.cgImage else {
            throw VisionOCRServiceError.missingCGImage
        }

        let cgImage = removeRedInk(from: originalCGImage) ?? originalCGImage
        let orientations: [(String, CGImagePropertyOrientation)] = [
            ("up", .up),
            ("right", .right),
            ("left", .left),
            ("down", .down)
        ]

        let runs = try orientations.map { name, orientation in
            try recognize(cgImage: cgImage, orientationName: name, orientation: orientation)
        }

        guard let bestRun = runs.max(by: { $0.score < $1.score }),
              !bestRun.candidates.isEmpty
        else {
            throw VisionOCRServiceError.noText
        }

        return bestRun.candidates
    }

    private func recognize(
        cgImage: CGImage,
        orientationName: String,
        orientation: CGImagePropertyOrientation
    ) throws -> OCRRun {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.006

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw VisionOCRServiceError.failed(error.localizedDescription)
        }

        let items = (request.results ?? [])
            .compactMap { observation -> OCRItem? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }

                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return nil
                }

                return OCRItem(
                    text: text,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }

        return OCRRun(
            orientationName: orientationName,
            orientation: orientation,
            items: items,
            candidates: parseRecords(from: items)
        )
    }

    private func removeRedInk(from cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])

            if isRedInk(red: red, green: green, blue: blue) {
                pixels[index] = 255
                pixels[index + 1] = 255
                pixels[index + 2] = 255
                pixels[index + 3] = 255
            }
        }

        return context.makeImage()
    }

    private func isRedInk(red: Int, green: Int, blue: Int) -> Bool {
        red > 75 &&
            red > green + 12 &&
            red > blue + 10 &&
            Double(red) > Double(green) * 1.12 &&
            Double(red) > Double(blue) * 1.08
    }

    private func parseRecords(from items: [OCRItem]) -> [OCRCandidate] {
        let layout = inferTableLayout(items)

        return groupRows(items).compactMap { row -> OCRCandidate? in
            let joined = row.map(\.text).joined(separator: " ")
            guard let phone = normalizePhone(joined) else {
                return nil
            }

            let phoneItem = row.first { normalizePhone($0.text) != nil } ?? row.min { lhs, rhs in
                abs(lhs.centerX - 0.5) < abs(rhs.centerX - 0.5)
            }
            guard let phoneItem else {
                return nil
            }

            let leftItems = row.filter { $0.centerX < phoneItem.centerX - 0.02 }
            let rightItems = row.filter { $0.centerX > phoneItem.centerX + 0.02 }
            let leftHasAddress = leftItems.contains { looksLikeAddress($0.text) }
            let rightHasAddress = rightItems.contains { looksLikeAddress($0.text) }

            let companyItems: [OCRItem]
            let categoryItems: [OCRItem]

            if layout.companySide == .right {
                companyItems = rightItems
                categoryItems = leftItems.filter { !looksLikeAddress($0.text) }
            } else if layout.companySide == .left {
                companyItems = leftItems
                categoryItems = rightItems.filter { !looksLikeAddress($0.text) }
            } else if leftHasAddress && !rightHasAddress {
                companyItems = rightItems
                categoryItems = leftItems.filter { !looksLikeAddress($0.text) }
            } else if rightHasAddress && !leftHasAddress {
                companyItems = leftItems
                categoryItems = rightItems.filter { !looksLikeAddress($0.text) }
            } else {
                let leftScore = businessNameScore(leftItems)
                let rightScore = businessNameScore(rightItems)
                if leftScore >= rightScore {
                    companyItems = leftItems
                    categoryItems = rightItems
                } else {
                    companyItems = rightItems
                    categoryItems = leftItems
                }
            }

            let companyName = cleanupCell(companyItems.map(\.text).joined(separator: " "))
            let category = cleanupCell(categoryItems.map(\.text).joined(separator: " "))

            guard !companyName.isEmpty || !category.isEmpty else {
                return nil
            }

            let averageConfidence = row.map(\.confidence).reduce(0, +) / Float(max(row.count, 1))

            return OCRCandidate(
                companyName: companyName,
                phoneNumber: phone,
                category: category,
                normalizedPhone: PhoneFormat.digits(phone),
                confidence: averageConfidence,
                rawText: joined
            )
        }
    }

    private func normalizePhone(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: phonePattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text)
        else {
            return nil
        }

        let candidate = String(text[matchRange])
        return PhoneFormat.standardize(candidate)
    }

    private func groupRows(_ items: [OCRItem]) -> [[OCRItem]] {
        let sorted = items.sorted { $0.centerY < $1.centerY }
        var rows: [[OCRItem]] = []
        let tolerance = max(0.012, medianHeight(items) * 0.9)

        for item in sorted {
            if let index = rows.firstIndex(where: { row in
                abs(row.map(\.centerY).reduce(0, +) / Double(row.count) - item.centerY) <= tolerance
            }) {
                rows[index].append(item)
            } else {
                rows.append([item])
            }
        }

        return rows.map { $0.sorted { $0.centerX < $1.centerX } }
    }

    private func medianHeight(_ items: [OCRItem]) -> Double {
        let heights = items.map(\.height).sorted()
        guard !heights.isEmpty else {
            return 0.02
        }
        return heights[heights.count / 2]
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        return sorted[sorted.count / 2]
    }

    private func inferTableLayout(_ items: [OCRItem]) -> TableLayout {
        let phoneCenters = items.compactMap { item -> Double? in
            normalizePhone(item.text) == nil ? nil : item.centerX
        }
        guard let phoneCenter = median(phoneCenters) else {
            return TableLayout(companySide: nil)
        }

        let addressCenters = items
            .filter { looksLikeAddress($0.text) }
            .map(\.centerX)
        guard let addressCenter = median(addressCenters) else {
            return TableLayout(companySide: nil)
        }

        return TableLayout(companySide: addressCenter < phoneCenter ? .right : .left)
    }

    private func cleanupCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[\|\[\]{}]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"대전광역시\s*서구[^\t]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"대전광역시\s*중구[^\t]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeAddress(_ text: String) -> Bool {
        text.range(
            of: #"서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충청|전라|경상|제주|특별시|광역시|시\s|군\s|구\s|읍\s|면\s|동\s|로\s|길\s"#,
            options: .regularExpression
        ) != nil
    }

    private func businessNameScore(_ items: [OCRItem]) -> Int {
        let text = cleanupCell(items.filter { !looksLikeAddress($0.text) }.map(\.text).joined(separator: " "))
        let hangul = text.filter { String($0).range(of: #"[가-힣]"#, options: .regularExpression) != nil }.count
        let punctuationPenalty = text.filter { ",:;.!?".contains($0) }.count * 2
        return hangul + min(text.count, 20) - punctuationPenalty
    }
}
