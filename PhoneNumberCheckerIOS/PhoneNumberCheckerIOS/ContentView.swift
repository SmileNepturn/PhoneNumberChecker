import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var store = PhoneStore()
    @State private var selectedImage: UIImage?
    @State private var imagePickerSource: PickerSource?
    @State private var isRecognizing = false
    @State private var selectedStatus: CallStatus = .missed
    @State private var alertMessage: String?
    @State private var showingResetConfirmation = false
    @State private var selectedTab = 0

    private let ocrService = VisionOCRService()

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
                    selectedImage = image
                }
            }
            .alert("알림", isPresented: alertBinding) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
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
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.secondary.opacity(0.25), lineWidth: 1)
                        }

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
            StatBox(title: "대기", value: "\(store.reviewQueue.count)")
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let candidate = store.currentCandidate {
                VStack(alignment: .leading, spacing: 12) {
                    Text("검토 대기 \(store.reviewQueue.count)건")
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
                        selectedStatus = .missed
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
            } else {
                ContentUnavailableView(
                    "검토할 전화번호가 없습니다",
                    systemImage: "checkmark.circle",
                    description: Text("사진을 찍거나 이미지를 선택해 OCR 추출을 먼저 진행하세요.")
                )
            }
        }
    }

    private var historyView: some View {
        List {
            ForEach(store.contacts.sorted(by: { $0.updatedAt > $1.updatedAt })) { contact in
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
                }
                .padding(.vertical, 4)
            }
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
                let candidates = try await ocrService.recognizeRecords(from: image)
                store.importCandidates(candidates)
                selectedTab = 1
            } catch {
                alertMessage = error.localizedDescription
            }

            isRecognizing = false
        }
    }
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
