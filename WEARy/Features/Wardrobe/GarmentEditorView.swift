import PhotosUI
import SwiftData
import SwiftUI

struct GarmentEditorView: View {
    private enum RegistrationMode: String, CaseIterable, Identifiable {
        case quick = "빠른 등록"
        case purchase = "새로 산 옷"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let garment: Garment?
    @State private var mode: RegistrationMode
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
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
    @State private var keepAdding = false
    @State private var showingSavedConfirmation = false
    @State private var saveError: String?

    init(garment: Garment? = nil) {
        self.garment = garment
        let isEditing = garment != nil
        _mode = State(initialValue: isEditing ? .purchase : .quick)
        _imageData = State(initialValue: garment?.imageData)
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
    }

    var body: some View {
        NavigationStack {
            Form {
                if garment == nil {
                    Section {
                        Picker("등록 방식", selection: $mode) {
                            ForEach(RegistrationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("저장 후 다음 옷 등록", isOn: $keepAdding)
                    } footer: {
                        Text(mode == .quick
                             ? "기존 옷장은 사진과 기본 정보만 빠르게 등록할 수 있어요."
                             : "구매 정보까지 기록하면 1회 착용 비용을 확인할 수 있어요.")
                    }
                }

                Section("옷 사진") {
                    GarmentPhotoPreview(imageData: imageData, colorHex: colorHex)

                    PhotosPicker("사진 보관함 열기", selection: $selectedPhoto, matching: .images)

                    if imageData != nil {
                        Button("사진 제거", role: .destructive) {
                            imageData = nil
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

                if mode == .purchase || garment != nil {
                    Section("구매 정보") {
                        DatePicker("구매일", selection: $purchaseDate, displayedComponents: .date)
                        TextField("구매 가격", text: $purchasePrice)
                            .keyboardType(.numberPad)
                        TextField("사이즈", text: $size)
                            .textInputAutocapitalization(.characters)
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
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run { imageData = data }
                    }
                }
            }
            .alert("옷을 저장했어요", isPresented: $showingSavedConfirmation) {
                Button("다음 옷 등록", role: .cancel) { }
            } message: {
                Text("사진과 기본 정보를 이어서 입력해 주세요.")
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
            garment.purchaseDate = purchaseDate
            garment.purchasePrice = parsedPrice
            garment.size = size
            garment.season = season
            garment.status = status
            garment.imageData = imageData
        } else {
            let newGarment = Garment(
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                colorName: colorName,
                colorHex: colorHex,
                purchaseDate: mode == .purchase ? purchaseDate : nil,
                purchasePrice: mode == .purchase ? parsedPrice : nil,
                size: mode == .purchase ? size : "",
                season: season,
                imageData: imageData
            )
            modelContext.insert(newGarment)
        }

        do {
            try modelContext.save()
            if garment == nil && keepAdding {
                resetForNextGarment()
                showingSavedConfirmation = true
            } else {
                dismiss()
            }
        } catch {
            saveError = "저장하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func resetForNextGarment() {
        selectedPhoto = nil
        imageData = nil
        name = ""
        brand = ""
        category = .top
        colorName = "블랙"
        colorHex = "343434"
        purchaseDate = .now
        purchasePrice = ""
        size = ""
        season = "사계절"
        status = .active
        saveError = nil
    }
}

private struct GarmentPhotoPreview: View {
    let imageData: Data?
    let colorHex: String

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 38, weight: .light))
                    Text("사진 보관함에서 선택")
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
