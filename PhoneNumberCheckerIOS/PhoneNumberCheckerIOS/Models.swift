import Foundation
import ImageIO
import Vision

enum CallStatus: String, CaseIterable, Codable, Identifiable {
    case missed
    case rejected
    case accepted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .missed:
            return "부재중"
        case .rejected:
            return "거절"
        case .accepted:
            return "승락"
        }
    }
}

struct OCRCandidate: Identifiable, Codable, Hashable {
    var id = UUID()
    var companyName: String
    var phoneNumber: String
    var category: String
    var normalizedPhone: String
    var confidence: Float
    var rawText: String
}

struct StoredContact: Identifiable, Codable, Hashable {
    var id = UUID()
    var companyName: String
    var phoneNumber: String
    var normalizedPhone: String
    var category: String
    var status: CallStatus
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date
}

struct OCRItem {
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    var x: Double { boundingBox.origin.x }
    var y: Double { boundingBox.origin.y }
    var width: Double { boundingBox.width }
    var height: Double { boundingBox.height }
    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
}

struct OCRRun {
    let orientationName: String
    let orientation: CGImagePropertyOrientation
    let items: [OCRItem]
    let candidates: [OCRCandidate]

    var score: Int {
        let phoneScore = candidates.count * 20
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
