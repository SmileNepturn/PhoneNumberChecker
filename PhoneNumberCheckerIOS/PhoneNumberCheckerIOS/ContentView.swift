import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var store = PhoneStore()
    @State private var selectedImage: UIImage?
    @State private var roiRect = Self.defaultROIRect
    @State private var imagePickerSource: PickerSource?
    @State private var isRecognizing = false
    @State private var selectedStatus: CallStatus = .missed
    @State private var alertMessage: String?
    @State private var showingResetConfirmation = false
    @State private var selectedTab = 0
    @State private var historySearchText = ""

    private let ocrService = VisionOCRService()
    private static let defaultROIRect = CGRect(x: 0.05, y: 0.08, width: 0.9, height: 0.84)

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                captureView
                    .tabItem { Label("촬영", systemImage: "camera") }
                    .tag(0)

                reviewView
                    .tabItem { Label("검토", systemImage: "checklist") }
                    .tag(1)

                historyView
                    .tabItem { Label("이력", systemImage: "tray.full") }
                    .tag(2)
            }
            .navigationTitle("전화번호 OCR DB")
            .toolbar {
                Button("DB 초기화", role: .destructive) {
                    showingResetConfirmation = true
                }
            }
            .confirmationDialog("저장된 전화번호 DB를 모두 삭제할까요?", isPresented: $showingResetConfirmation) {
                Button("초기화", role: .destructive) {
                    store.resetDatabase()
                }
            }
            .sheet(item: $imagePickerSource) { source in
                ImagePicker(sourceType: source.uiImagePickerSourceType) { image in
                    selectedImage = image.normalizedForOCR()
                    roiRect = Self.defaultROIRect
                }
            }
            .alert("알림", isPresented: alertBinding) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                syncSelectedStatusWithCurrent()
            }
            .onChange(of: store.currentReviewCandidate?.id) { _ in
                syncSelectedStatusWithCurrent()
            }
        }
    }

    private var captureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statsView

                HStack(spacing: 12) {
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            imagePickerSource = .camera
                        } else {
                            alertMessage = "이 기기에서는 카메라를 열 수 없습니다. 사진 보관함에서 선택해주세요."
                        }
                    } label: {
                        Label("사진찍기", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        imagePickerSource = .photoLibrary
                    } label: {
                        Label("이미지 선택", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Text("사진은 저장하지 않고 OCR 처리 후 텍스트와 전화번호만 DB에 저장합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let selectedImage {
                    ROISelectionView(image: selectedImage, roiRect: $roiRect)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("초록 영역을 업체명과 전화번호가 있는 표 영역에 맞춘 뒤 추출하세요. 영역 안쪽을 끌면 이동하고, 꼭지점을 끌면 크기가 바뀝니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            roiRect = Self.defaultROIRect
                        } label: {
                            Label("영역 초기화", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            runOCR(selectedImage)
                        } label: {
                            if isRecognizing {
                                Label("OCR 처리 중", systemImage: "hourglass")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("추출", systemImage: "text.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isRecognizing)
                        .buttonStyle(.borderedProminent)
                    }
                }

                if isRecognizing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                if !store.lastImportMessage.isEmpty {
                    Text(store.lastImportMessage)
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }
            .padding()
        }
    }

    private var statsView: some View {
        HStack(spacing: 12) {
            StatBox(title: "전체 등록", value: "\(store.totalCount)")
            StatBox(title: "오늘 처리", value: "\(store.todayProcessedCount)")
            StatBox(title: "대기", value: "\(store.visibleReviewCount)")
        }
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !store.reviewQueue.isEmpty {
                    reviewFilterView
                }

                if let item = store.currentReviewCandidate {
                    let candidate = item.candidate

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("검토 대기 \(store.visibleReviewCount)건")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        MatchBadge(item: item)
                    }

                    if let existingContact = item.existingContact {
                        ExistingContactSummary(contact: existingContact)
                    }

                    Text("현재 항목")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    TextField("업체명", text: Binding(
                        get: { store.currentCandidate?.companyName ?? "" },
                        set: { store.updateCurrent(companyName: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField("전화번호", text: Binding(
                        get: { store.currentCandidate?.phoneNumber ?? "" },
                        set: { store.updateCurrent(phoneNumber: $0) }
                    ))
                    .keyboardType(.phonePad)
                    .textFieldStyle(.roundedBorder)

                    TextField("업종/주소", text: Binding(
                        get: { store.currentCandidate?.category ?? "" },
                        set: { store.updateCurrent(category: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Picker("처리 결과", selection: $selectedStatus) {
                        ForEach(CallStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        store.saveCurrent(status: selectedStatus)
                        syncSelectedStatusWithCurrent()
                    } label: {
                        Label("다음", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    DisclosureGroup("OCR 원문 보기") {
                        Text(candidate.rawText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                }

                    reviewResultList
            } else {
                ContentUnavailableView(
                    store.showOnlyNewCandidates ? "신규 전화번호가 없습니다" : "검토할 전화번호가 없습니다",
                    systemImage: store.showOnlyNewCandidates ? "line.3.horizontal.decrease.circle" : "checkmark.circle",
                    description: Text(store.showOnlyNewCandidates ? "전체 보기를 끄면 기존 DB와 매칭된 번호도 확인할 수 있습니다." : "사진을 찍거나 이미지를 선택해 OCR 추출을 먼저 진행하세요.")
                )
            }
            }
            .padding()
        }
    }

    private var reviewFilterView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("이전 DB에 없는 번호만 보기", isOn: $store.showOnlyNewCandidates)
                .font(.headline)

            HStack(spacing: 12) {
                StatBox(title: "감지", value: "\(store.reviewQueue.count)")
                StatBox(title: "기존", value: "\(store.importedExistingCount)")
                StatBox(title: "신규", value: "\(store.importedNewCount)")
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    private var reviewResultList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.showOnlyNewCandidates ? "신규 번호 목록" : "추출 결과 전체")
                .font(.headline)

            ForEach(store.visibleReviewQueue) { item in
                ReviewCandidateRow(item: item)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    private var historyView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("업체명 또는 전화번호 검색", text: $historySearchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !historySearchText.isEmpty {
                    Button {
                        historySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                if filteredHistoryContacts.isEmpty {
                    ContentUnavailableView(
                        historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "저장된 이력이 없습니다" : "검색 결과가 없습니다",
                        systemImage: "magnifyingglass",
                        description: Text("업체명 또는 전화번호로 검색할 수 있습니다.")
                    )
                } else {
                    ForEach(filteredHistoryContacts) { contact in
                        NavigationLink {
                            HistoryDetailView(store: store, contactID: contact.id)
                        } label: {
                            HistoryContactRow(contact: contact)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var filteredHistoryContacts: [StoredContact] {
        let sortedContacts = store.contacts.sorted(by: { $0.updatedAt > $1.updatedAt })
        let query = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return sortedContacts
        }

        let queryDigits = PhoneFormat.digits(query)
        return sortedContacts.filter { contact in
            contact.companyName.localizedCaseInsensitiveContains(query)
                || contact.phoneNumber.localizedCaseInsensitiveContains(query)
                || (!queryDigits.isEmpty && contact.normalizedPhone.contains(queryDigits))
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { newValue in
                if !newValue {
                    alertMessage = nil
                }
            }
        )
    }

    private func runOCR(_ image: UIImage) {
        isRecognizing = true

        Task {
            do {
                let ocrImage = image.cropped(to: roiRect) ?? image
                let candidates = try await ocrService.recognizeRecords(from: ocrImage)
                store.importCandidates(candidates)
                selectedTab = 1
            } catch {
                alertMessage = error.localizedDescription
            }

            isRecognizing = false
        }
    }

    private func syncSelectedStatusWithCurrent() {
        selectedStatus = store.currentReviewCandidate?.initialStatus ?? .missed
    }
}

private struct ROISelectionView: View {
    let image: UIImage
    @Binding var roiRect: CGRect
    @State private var dragStartRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let imageFrame = fittedImageFrame(containerSize: containerSize)
            let selectionFrame = denormalized(roiRect, in: imageFrame)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: containerSize.width, height: containerSize.height)

                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .offset(x: imageFrame.minX, y: imageFrame.minY)

                Rectangle()
                    .fill(Color.teal.opacity(0.18))
                    .frame(width: selectionFrame.width, height: selectionFrame.height)
                    .offset(x: selectionFrame.minX, y: selectionFrame.minY)
                    .gesture(moveGesture(imageFrame: imageFrame))

                Rectangle()
                    .stroke(Color.teal, lineWidth: 3)
                    .frame(width: selectionFrame.width, height: selectionFrame.height)
                    .offset(x: selectionFrame.minX, y: selectionFrame.minY)
                    .allowsHitTesting(false)

                ForEach(ROICorner.allCases) { corner in
                    Circle()
                        .fill(Color.teal)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                        }
                        .position(corner.point(in: selectionFrame))
                        .gesture(resizeGesture(corner: corner, imageFrame: imageFrame))
                }
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .background(Color.black.opacity(0.08))
    }

    private func fittedImageFrame(containerSize: CGSize) -> CGRect {
        let imageAspect = image.size.width / max(image.size.height, 1)
        let containerAspect = containerSize.width / max(containerSize.height, 1)

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGRect(x: 0, y: (containerSize.height - height) / 2, width: width, height: height)
        }

        let height = containerSize.height
        let width = height * imageAspect
        return CGRect(x: (containerSize.width - width) / 2, y: 0, width: width, height: height)
    }

    private func denormalized(_ rect: CGRect, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + rect.minX * imageFrame.width,
            y: imageFrame.minY + rect.minY * imageFrame.height,
            width: rect.width * imageFrame.width,
            height: rect.height * imageFrame.height
        )
    }

    private func moveGesture(imageFrame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let startRect = dragStartRect ?? roiRect
                dragStartRect = startRect

                let dx = value.translation.width / max(imageFrame.width, 1)
                let dy = value.translation.height / max(imageFrame.height, 1)
                roiRect.origin.x = clamp(startRect.origin.x + dx, min: 0, max: 1 - startRect.width)
                roiRect.origin.y = clamp(startRect.origin.y + dy, min: 0, max: 1 - startRect.height)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func resizeGesture(corner: ROICorner, imageFrame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let startRect = dragStartRect ?? roiRect
                dragStartRect = startRect

                let dx = value.translation.width / max(imageFrame.width, 1)
                let dy = value.translation.height / max(imageFrame.height, 1)
                roiRect = resized(startRect, corner: corner, dx: dx, dy: dy)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func resized(_ rect: CGRect, corner: ROICorner, dx: CGFloat, dy: CGFloat) -> CGRect {
        let minimumSize: CGFloat = 0.08
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch corner {
        case .topLeft:
            minX = clamp(rect.minX + dx, min: 0, max: rect.maxX - minimumSize)
            minY = clamp(rect.minY + dy, min: 0, max: rect.maxY - minimumSize)
        case .topRight:
            maxX = clamp(rect.maxX + dx, min: rect.minX + minimumSize, max: 1)
            minY = clamp(rect.minY + dy, min: 0, max: rect.maxY - minimumSize)
        case .bottomLeft:
            minX = clamp(rect.minX + dx, min: 0, max: rect.maxX - minimumSize)
            maxY = clamp(rect.maxY + dy, min: rect.minY + minimumSize, max: 1)
        case .bottomRight:
            maxX = clamp(rect.maxX + dx, min: rect.minX + minimumSize, max: 1)
            maxY = clamp(rect.maxY + dy, min: rect.minY + minimumSize, max: 1)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private enum ROICorner: CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String {
        switch self {
        case .topLeft:
            return "topLeft"
        case .topRight:
            return "topRight"
        case .bottomLeft:
            return "bottomLeft"
        case .bottomRight:
            return "bottomRight"
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, minimum), maximum)
}

private struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct MatchBadge: View {
    let item: ReviewCandidate

    var body: some View {
        Text(item.matchTitle)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(item.isNew ? .green : .orange)
            .background((item.isNew ? Color.green : Color.orange).opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ExistingContactSummary: View {
    let contact: StoredContact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("이전에 등록된 번호입니다")
                .font(.subheadline.bold())
            Text("\(contact.companyName.isEmpty ? "(업체명 없음)" : contact.companyName) · \(contact.phoneNumber) · \(contact.status.title)")
                .font(.subheadline)
            Text("마지막 처리: \(contact.updatedAt.formatted(date: .numeric, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct HistoryContactRow: View {
    let contact: StoredContact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(contact.companyName.isEmpty ? "(업체명 없음)" : contact.companyName)
                    .font(.headline)

                Spacer()

                Text(contact.status.title)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.teal.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(contact.phoneNumber)
                .font(.body.monospacedDigit())

            if !contact.category.isEmpty {
                Text(contact.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("마지막 처리: \(contact.updatedAt.formatted(date: .numeric, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryDetailView: View {
    @ObservedObject var store: PhoneStore
    let contactID: StoredContact.ID
    @State private var isEditing = false
    @State private var selectedStatus: CallStatus = .missed

    private var contact: StoredContact? {
        store.contacts.first { $0.id == contactID }
    }

    var body: some View {
        Group {
            if let contact {
                Form {
                    Section("업체 정보") {
                        LabeledContent("업체명", value: contact.companyName.isEmpty ? "(업체명 없음)" : contact.companyName)
                        LabeledContent("전화번호", value: contact.phoneNumber)
                        if !contact.category.isEmpty {
                            LabeledContent("업종/주소", value: contact.category)
                        }
                    }

                    Section("처리 상태") {
                        if isEditing {
                            Picker("처리 결과", selection: $selectedStatus) {
                                ForEach(CallStatus.allCases) { status in
                                    Text(status.title).tag(status)
                                }
                            }
                            .pickerStyle(.segmented)

                            Button {
                                store.updateContactStatus(contactID: contact.id, status: selectedStatus)
                                isEditing = false
                            } label: {
                                Label("업데이트", systemImage: "checkmark.circle.fill")
                            }
                        } else {
                            LabeledContent("상태", value: contact.status.title)
                        }
                    }

                    Section("날짜") {
                        LabeledContent("최초 등록", value: contact.createdAt.formatted(date: .numeric, time: .shortened))
                        LabeledContent("마지막 처리", value: contact.updatedAt.formatted(date: .numeric, time: .shortened))
                        LabeledContent("마지막 발견", value: contact.lastSeenAt.formatted(date: .numeric, time: .shortened))
                    }
                }
                .navigationTitle("이력 상세")
                .toolbar {
                    Button(isEditing ? "취소" : "수정") {
                        selectedStatus = contact.status
                        isEditing.toggle()
                    }
                }
                .onAppear {
                    selectedStatus = contact.status
                }
            } else {
                ContentUnavailableView("이력을 찾을 수 없습니다", systemImage: "tray")
            }
        }
    }
}

private struct ReviewCandidateRow: View {
    let item: ReviewCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.candidate.companyName.isEmpty ? "(업체명 없음)" : item.candidate.companyName)
                    .font(.subheadline.bold())
                Text(item.candidate.phoneNumber)
                    .font(.subheadline.monospacedDigit())
                if !item.candidate.category.isEmpty {
                    Text(item.candidate.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let existing = item.existingContact {
                    Text("기존 처리: \(existing.status.title) · \(existing.updatedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            MatchBadge(item: item)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(item.isNew ? Color.green.opacity(0.06) : Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension UIImage {
    func normalizedForOCR() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func cropped(to normalizedRect: CGRect) -> UIImage? {
        let normalizedImage = normalizedForOCR()
        guard let cgImage = normalizedImage.cgImage else {
            return nil
        }

        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let cropRect = CGRect(
            x: normalizedRect.minX * imageBounds.width,
            y: normalizedRect.minY * imageBounds.height,
            width: normalizedRect.width * imageBounds.width,
            height: normalizedRect.height * imageBounds.height
        )
        .integral
        .intersection(imageBounds)

        guard cropRect.width > 0,
              cropRect.height > 0,
              let cropped = cgImage.cropping(to: cropRect)
        else {
            return nil
        }

        return UIImage(cgImage: cropped, scale: normalizedImage.scale, orientation: .up)
    }
}

private enum PickerSource: Identifiable {
    case camera
    case photoLibrary

    var id: String {
        switch self {
        case .camera:
            return "camera"
        case .photoLibrary:
            return "photoLibrary"
        }
    }

    var uiImagePickerSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return .camera
        case .photoLibrary:
            return .photoLibrary
        }
    }
}
