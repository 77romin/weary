import PhotosUI
import SwiftData
import SwiftUI

struct GarmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let garment: Garment?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var cutoutImageData: Data?
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var cameraMessage: String?
    @State private var isGeneratingCutout = false
    @State private var didAttemptCutout = false
    @State private var name: String
    @State private var brand: String
    @State private var category: GarmentCategory
    @State private var colorName: String
    @State private var colorHex: String
    @State private var purchaseDate: Date
    @State private var purchasePrice: String
    @State private var size: String
    @State private var season: String
    @State private var status: GarmentStatus
    @State private var hasPurchaseDate: Bool
    @State private var saveError: String?

    init(garment: Garment? = nil) {
        self.garment = garment
        _imageData = State(initialValue: garment?.imageData)
        _cutoutImageData = State(initialValue: garment?.cutoutImageData)
        _didAttemptCutout = State(initialValue: garment?.imageData != nil)
        _name = State(initialValue: garment?.name ?? "")
        _brand = State(initialValue: garment?.brand ?? "")
        _category = State(initialValue: garment?.category ?? .top)
        _colorName = State(initialValue: garment?.colorName ?? "블랙")
        _colorHex = State(initialValue: garment?.colorHex ?? "343434")
        _purchaseDate = State(initialValue: garment?.purchaseDate ?? .now)
        _purchasePrice = State(initialValue: garment?.purchasePrice.map(String.init) ?? "")
        _size = State(initialValue: garment?.size ?? "")
        _season = State(initialValue: garment?.season ?? "사계절")
        _status = State(initialValue: garment?.status ?? .active)
        _hasPurchaseDate = State(initialValue: garment?.purchaseDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("옷 사진") {
                    GarmentPhotoPreview(
                        imageData: cutoutImageData ?? imageData,
                        colorHex: colorHex,
                        showsTransparentBackground: cutoutImageData != nil
                    )

                    if isGeneratingCutout {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("옷만 깔끔하게 분리하는 중이에요")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if cutoutImageData != nil {
                        Label("배경 제거 완료", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    } else if didAttemptCutout && imageData != nil {
                        Label("배경을 분리하지 못해 원본 사진으로 저장해요", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button {
                            requestCamera()
                        } label: {
                            Label("카메라로 촬영", systemImage: "camera.fill")
                        }
                        .accessibilityIdentifier("garment.camera")
                        .buttonStyle(.borderless)

                        Spacer()

                        Button {
                            showingPhotoLibrary = true
                        } label: {
                            Label("사진 보관함", systemImage: "photo.on.rectangle")
                        }
                        .accessibilityIdentifier("garment.library")
                        .buttonStyle(.borderless)
                    }

                    if imageData != nil {
                        Button("사진 제거", role: .destructive) {
                            imageData = nil
                            cutoutImageData = nil
                            didAttemptCutout = false
                            selectedPhoto = nil
                        }
                    }
                }

                Section("필수 정보") {
                    TextField("옷 이름", text: $name)
                    Picker("카테고리", selection: $category) {
                        ForEach(GarmentCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.symbol)
                                .tag(category)
                        }
                    }
                }

                Section("스타일 정보") {
                    TextField("브랜드", text: $brand)
                    TextField("색상 이름", text: $colorName)
                    Picker("계절", selection: $season) {
                        ForEach(["봄", "여름", "가을", "겨울", "봄 · 가을", "가을 · 겨울", "사계절"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }

                Section {
                    Toggle("구매일 입력", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("구매일", selection: $purchaseDate, displayedComponents: .date)
                    }
                    TextField("구매 가격 (선택)", text: $purchasePrice)
                        .keyboardType(.numberPad)
                    TextField("사이즈 (선택)", text: $size)
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("구매 정보 · 선택")
                } footer: {
                    Text("가격을 입력하면 착용 횟수에 따라 1회당 착용 비용을 계산해 드려요.")
                }

                if garment != nil {
                    Section("관리") {
                        Picker("상태", selection: $status) {
                            ForEach(GarmentStatus.allCases) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle(garment == nil ? "새 옷 등록" : "옷 정보 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .fontWeight(.bold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingCutout)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            saveError = "선택한 사진을 불러올 수 없어요."
                            return
                        }
                        await processPhoto(data)
                    } catch {
                        saveError = "사진을 불러오는 중 문제가 생겼어요."
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    selectedPhoto = nil
                    Task { await processPhoto(data) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showingPhotoLibrary,
                selection: $selectedPhoto,
                matching: .images
            )
            .alert("카메라를 열 수 없어요", isPresented: Binding(
                get: { cameraMessage != nil },
                set: { if !$0 { cameraMessage = nil } }
            )) {
                Button("확인") { cameraMessage = nil }
            } message: {
                Text(cameraMessage ?? "")
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPrice = Int(purchasePrice.replacingOccurrences(of: ",", with: ""))

        if let garment {
            garment.name = trimmedName
            garment.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            garment.category = category
            garment.colorName = colorName
            garment.purchaseDate = hasPurchaseDate ? purchaseDate : nil
            garment.purchasePrice = parsedPrice
            garment.size = size
            garment.season = season
            garment.status = status
            garment.imageData = imageData
            garment.cutoutImageData = cutoutImageData
        } else {
            let newGarment = Garment(
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                colorName: colorName,
                colorHex: colorHex,
                purchaseDate: hasPurchaseDate ? purchaseDate : nil,
                purchasePrice: parsedPrice,
                size: size,
                season: season,
                imageData: imageData,
                cutoutImageData: cutoutImageData
            )
            modelContext.insert(newGarment)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = "저장하지 못했어요. 다시 시도해 주세요."
        }
    }

    @MainActor
    private func processPhoto(_ data: Data) async {
        imageData = data
        cutoutImageData = nil
        didAttemptCutout = false
        saveError = nil
        isGeneratingCutout = true
        cutoutImageData = await GarmentCutoutService.shared.makeCutout(from: data)
        isGeneratingCutout = false
        didAttemptCutout = true
    }

    private func requestCamera() {
        Task {
            switch await CameraAccess.request() {
            case .ready:
                showingCamera = true
            case .unavailable:
                cameraMessage = "이 기기에서는 카메라를 사용할 수 없어요. 사진 보관함에서 이미지를 선택해 주세요."
            case .denied:
                cameraMessage = "설정에서 WEARy의 카메라 접근을 허용한 뒤 다시 시도해 주세요."
            }
        }
    }

}

private struct GarmentPhotoPreview: View {
    let imageData: Data?
    let colorHex: String
    let showsTransparentBackground: Bool

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(showsTransparentBackground ? 14 : 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(Color(hex: "E9E5DD"))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 38, weight: .light))
                    Text("사진을 촬영하거나 선택")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(WEARyTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background(Color(hex: colorHex).opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}
