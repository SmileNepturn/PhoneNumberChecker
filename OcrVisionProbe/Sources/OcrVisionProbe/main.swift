import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Vision

struct OCRItem: Codable {
    let text: String
    let confidence: Float
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
}

struct BusinessRecord: Codable {
    let companyName: String
    let phoneNumber: String
    let category: String
    let confidence: Float
}

struct OCRRun {
    let orientationName: String
    let orientation: CGImagePropertyOrientation
    let items: [OCRItem]
    let records: [BusinessRecord]

    var score: Int {
        let phoneScore = records.count * 20
        let textScore = min(items.count, 120)
        let confidenceScore = Int((items.map(\.confidence).reduce(0, +) / Float(max(items.count, 1))) * 10)
        return phoneScore + textScore + confidenceScore
    }
}

enum ColumnSide: Equatable {
    case left
    case right
}

struct TableLayout {
    let companySide: ColumnSide?
}

enum ProbeError: Error, CustomStringConvertible {
    case missingImagePath
    case imageLoadFailed(String)
    case cgImageFailed(String)
    case visionFailed(String)

    var description: String {
        switch self {
        case .missingImagePath:
            return "Usage: swift run ocr-vision-probe <image-path> [--orientation auto|up|right|left|down] [--raw]"
        case .imageLoadFailed(let path):
            return "이미지를 읽을 수 없습니다: \(path)"
        case .cgImageFailed(let path):
            return "이미지를 CGImage로 변환할 수 없습니다: \(path)"
        case .visionFailed(let message):
            return "Vision OCR 실패: \(message)"
        }
    }
}

let phonePattern = #"(?:0\d{1,3})[-\s.]?\d{3,4}[-\s.]?\d{4}|(?:1[568]\d{2})[-\s.]?\d{4}"#
let phoneRegex = try NSRegularExpression(pattern: phonePattern)

func cgImage(from path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let image = NSImage(contentsOf: url) else {
        throw ProbeError.imageLoadFailed(path)
    }

    var rect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw ProbeError.cgImageFailed(path)
    }

    return cgImage
}

func imageRemovingRedInk(from cgImage: CGImage) -> CGImage? {
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

func isRedInk(red: Int, green: Int, blue: Int) -> Bool {
    red > 75 &&
    red > green + 12 &&
    red > blue + 10 &&
    Double(red) > Double(green) * 1.12 &&
    Double(red) > Double(blue) * 1.08
}

func recognize(cgImage: CGImage, orientationName: String, orientation: CGImagePropertyOrientation) throws -> OCRRun {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.006

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

    do {
        try handler.perform([request])
    } catch {
        throw ProbeError.visionFailed(error.localizedDescription)
    }

    let observations = request.results ?? []
    let items = observations.compactMap { observation -> OCRItem? in
        guard let candidate = observation.topCandidates(1).first else {
            return nil
        }
        let box = observation.boundingBox
        return OCRItem(
            text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: candidate.confidence,
            x: box.origin.x,
            y: box.origin.y,
            width: box.width,
            height: box.height
        )
    }
    .filter { !$0.text.isEmpty }

    return OCRRun(
        orientationName: orientationName,
        orientation: orientation,
        items: items,
        records: parseRecords(from: items)
    )
}

func normalizePhone(_ text: String) -> String? {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = phoneRegex.firstMatch(in: text, range: range),
          let matchRange = Range(match.range, in: text)
    else {
        return nil
    }

    let candidate = String(text[matchRange])
    let digits = candidate.filter(\.isNumber)

    switch digits.count {
    case 8:
        return "\(digits.prefix(4))-\(digits.suffix(4))"
    case 10:
        if digits.hasPrefix("02") {
            let a = digits.prefix(2)
            let b = digits.dropFirst(2).prefix(4)
            let c = digits.suffix(4)
            return "\(a)-\(b)-\(c)"
        } else {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(3)
            let c = digits.suffix(4)
            return "\(a)-\(b)-\(c)"
        }
    case 11:
        let a = digits.prefix(3)
        let b = digits.dropFirst(3).prefix(4)
        let c = digits.suffix(4)
        return "\(a)-\(b)-\(c)"
    case 12 where digits.hasPrefix("050"):
        let a = digits.prefix(4)
        let b = digits.dropFirst(4).prefix(4)
        let c = digits.suffix(4)
        return "\(a)-\(b)-\(c)"
    default:
        return nil
    }
}

func groupRows(_ items: [OCRItem]) -> [[OCRItem]] {
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

func medianHeight(_ items: [OCRItem]) -> Double {
    let heights = items.map(\.height).sorted()
    guard !heights.isEmpty else {
        return 0.02
    }
    return heights[heights.count / 2]
}

func median(_ values: [Double]) -> Double? {
    let sorted = values.sorted()
    guard !sorted.isEmpty else {
        return nil
    }
    return sorted[sorted.count / 2]
}

func parseRecords(from items: [OCRItem]) -> [BusinessRecord] {
    let layout = inferTableLayout(items)

    return groupRows(items).compactMap { row -> BusinessRecord? in
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

        let cleanedCompany = cleanupCell(companyItems.map(\.text).joined(separator: " "))
        let cleanedCategory = cleanupCell(categoryItems.map(\.text).joined(separator: " "))

        guard !cleanedCompany.isEmpty || !cleanedCategory.isEmpty else {
            return nil
        }

        let averageConfidence = row.map(\.confidence).reduce(0, +) / Float(max(row.count, 1))
        return BusinessRecord(
            companyName: cleanedCompany,
            phoneNumber: phone,
            category: cleanedCategory,
            confidence: averageConfidence
        )
    }
}

func inferTableLayout(_ items: [OCRItem]) -> TableLayout {
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

func cleanupCell(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"[\|\[\]{}]"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"대전광역시\s*서구[^\t]*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func looksLikeAddress(_ text: String) -> Bool {
    text.range(
        of: #"서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충청|전라|경상|제주|특별시|광역시|시\s|군\s|구\s|읍\s|면\s|동\s|로\s|길\s"#,
        options: .regularExpression
    ) != nil
}

func businessNameScore(_ items: [OCRItem]) -> Int {
    let text = cleanupCell(items.filter { !looksLikeAddress($0.text) }.map(\.text).joined(separator: " "))
    let hangul = text.filter { String($0).range(of: #"[가-힣]"#, options: .regularExpression) != nil }.count
    let punctuationPenalty = text.filter { ",:;.!?".contains($0) }.count * 2
    return hangul + min(text.count, 20) - punctuationPenalty
}

func selectedOrientations(_ value: String) -> [(String, CGImagePropertyOrientation)] {
    let all: [(String, CGImagePropertyOrientation)] = [
        ("up", .up),
        ("right", .right),
        ("left", .left),
        ("down", .down)
    ]

    if value == "auto" {
        return all
    }

    return all.filter { $0.0 == value }
}

func printResult(_ run: OCRRun, includeRaw: Bool) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let payload: [String: Any] = [
        "orientation": run.orientationName,
        "recordCount": run.records.count
    ]

    let metadata = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    print(String(data: metadata, encoding: .utf8) ?? "{}")

    let recordsData = try encoder.encode(run.records)
    print(String(data: recordsData, encoding: .utf8) ?? "[]")

    print("\n업체명\t전화번호\t업종\t신뢰도")
    for record in run.records {
        let confidence = String(format: "%.2f", record.confidence)
        print("\(record.companyName)\t\(record.phoneNumber)\t\(record.category)\t\(confidence)")
    }

    if includeRaw {
        let rawData = try encoder.encode(run.items)
        print("\nRAW OCR ITEMS")
        print(String(data: rawData, encoding: .utf8) ?? "[]")
    }
}

func main() throws {
    let arguments = CommandLine.arguments.dropFirst()
    guard let imagePath = arguments.first else {
        throw ProbeError.missingImagePath
    }

    var orientation = "auto"
    var includeRaw = false

    var iterator = arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        if argument == "--orientation", let value = iterator.next() {
            orientation = value
        } else if argument == "--raw" {
            includeRaw = true
        }
    }

    let originalImage = try cgImage(from: imagePath)
    let cgImage = imageRemovingRedInk(from: originalImage) ?? originalImage
    let runs = try selectedOrientations(orientation).map { name, orientation in
        try recognize(cgImage: cgImage, orientationName: name, orientation: orientation)
    }

    guard let bestRun = runs.max(by: { $0.score < $1.score }) else {
        throw ProbeError.visionFailed("선택 가능한 방향이 없습니다.")
    }

    try printResult(bestRun, includeRaw: includeRaw)
}

do {
    try main()
} catch let error as ProbeError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
