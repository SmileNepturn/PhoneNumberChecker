import Foundation

@MainActor
final class PhoneStore: ObservableObject {
    @Published private(set) var contacts: [StoredContact] = []
    @Published private(set) var reviewQueue: [ReviewCandidate] = []
    @Published var showOnlyNewCandidates = false
    @Published var lastImportMessage = ""

    private let fileName = "phone-db.json"

    init() {
        load()
    }

    var totalCount: Int {
        contacts.count
    }

    var todayProcessedCount: Int {
        let calendar = Calendar.current
        return contacts.filter { calendar.isDateInToday($0.updatedAt) }.count
    }

    var currentCandidate: OCRCandidate? {
        currentReviewCandidate?.candidate
    }

    var currentReviewCandidate: ReviewCandidate? {
        visibleReviewQueue.first
    }

    var visibleReviewQueue: [ReviewCandidate] {
        if showOnlyNewCandidates {
            return reviewQueue.filter(\.isNew)
        }

        return reviewQueue
    }

    var visibleReviewCount: Int {
        visibleReviewQueue.count
    }

    var importedNewCount: Int {
        reviewQueue.filter(\.isNew).count
    }

    var importedExistingCount: Int {
        reviewQueue.filter { !$0.isNew }.count
    }

    func importCandidates(_ candidates: [OCRCandidate]) {
        let uniqueCandidates = candidates.uniquedByPhone()
        var nextQueue: [ReviewCandidate] = []

        for candidate in uniqueCandidates {
            let existing = contacts.first { $0.normalizedPhone == candidate.normalizedPhone }
            nextQueue.append(ReviewCandidate(candidate: candidate, existingContact: existing))
        }

        reviewQueue = nextQueue
        lastImportMessage = "감지 \(uniqueCandidates.count)건, 기존 \(importedExistingCount)건, 신규 \(importedNewCount)건"
    }

    func updateCurrent(companyName: String? = nil, phoneNumber: String? = nil, category: String? = nil) {
        guard let currentID = currentReviewCandidate?.id,
              let index = reviewQueue.firstIndex(where: { $0.id == currentID })
        else {
            return
        }

        if let companyName {
            reviewQueue[index].candidate.companyName = companyName
        }

        if let phoneNumber {
            let formattedPhone = PhoneFormat.standardize(phoneNumber) ?? phoneNumber
            reviewQueue[index].candidate.phoneNumber = formattedPhone
            reviewQueue[index].candidate.normalizedPhone = PhoneFormat.digits(formattedPhone)
        }

        if let category {
            reviewQueue[index].candidate.category = category
        }
    }

    func saveCurrent(status: CallStatus) {
        guard let currentID = currentReviewCandidate?.id,
              let queueIndex = reviewQueue.firstIndex(where: { $0.id == currentID })
        else {
            return
        }

        let item = reviewQueue.remove(at: queueIndex)
        let candidate = item.candidate
        let now = Date()

        if let index = contacts.firstIndex(where: { $0.normalizedPhone == candidate.normalizedPhone }) {
            contacts[index].companyName = candidate.companyName
            contacts[index].phoneNumber = candidate.phoneNumber
            contacts[index].category = candidate.category
            contacts[index].status = status
            contacts[index].updatedAt = now
            contacts[index].lastSeenAt = now
        } else {
            contacts.append(
                StoredContact(
                    companyName: candidate.companyName,
                    phoneNumber: candidate.phoneNumber,
                    normalizedPhone: candidate.normalizedPhone,
                    category: candidate.category,
                    status: status,
                    createdAt: now,
                    updatedAt: now,
                    lastSeenAt: now
                )
            )
        }

        save()
    }

    func resetDatabase() {
        contacts = []
        reviewQueue = []
        showOnlyNewCandidates = false
        lastImportMessage = "DB를 초기화했습니다."
        save()
    }

    private func load() {
        do {
            let url = databaseURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            contacts = try decoder.decode([StoredContact].self, from: data)
        } catch {
            lastImportMessage = "DB를 읽지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(contacts)
            try data.write(to: databaseURL(), options: [.atomic])
        } catch {
            lastImportMessage = "DB 저장 실패: \(error.localizedDescription)"
        }
    }

    private func databaseURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(fileName)
    }
}

private extension Array where Element == OCRCandidate {
    func uniquedByPhone() -> [OCRCandidate] {
        var seen = Set<String>()
        var result: [OCRCandidate] = []

        for candidate in self where !candidate.normalizedPhone.isEmpty {
            if seen.insert(candidate.normalizedPhone).inserted {
                result.append(candidate)
            }
        }

        return result
    }
}

enum PhoneFormat {
    static func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    static func standardize(_ text: String) -> String? {
        let digits = digits(text)

        switch digits.count {
        case 8:
            return "\(digits.prefix(4))-\(digits.suffix(4))"
        case 10:
            if digits.hasPrefix("02") {
                let area = digits.prefix(2)
                let middle = digits.dropFirst(2).prefix(4)
                let suffix = digits.suffix(4)
                return "\(area)-\(middle)-\(suffix)"
            }

            let area = digits.prefix(3)
            let middle = digits.dropFirst(3).prefix(3)
            let suffix = digits.suffix(4)
            return "\(area)-\(middle)-\(suffix)"
        case 11:
            let area = digits.prefix(3)
            let middle = digits.dropFirst(3).prefix(4)
            let suffix = digits.suffix(4)
            return "\(area)-\(middle)-\(suffix)"
        case 12 where digits.hasPrefix("050"):
            let area = digits.prefix(4)
            let middle = digits.dropFirst(4).prefix(4)
            let suffix = digits.suffix(4)
            return "\(area)-\(middle)-\(suffix)"
        default:
            return nil
        }
    }
}
