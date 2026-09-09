import PhotosUI
import SwiftData
import SwiftUI

struct CaptureView: View {
    private enum Phase: Hashable {
        case ready, preview, analyzing, review, saved
        case failed(String)
    }

    private enum CameraReadiness: Equatable {
        case checking, ready, unavailable, denied
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Garment.createdAt) private var garments: [Garment]
    @State private var phase: Phase = .ready
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var cameraReadiness: CameraReadiness = .checking
    @State private var cameraMessage: String?
    @State private var wornAt = Date.now
    @State private var groups: [DetectedGarmentGroup] = []
    @State private var editingGroupID: UUID?
    @State private var showingGarmentPicker = false
    @State private var showingNewGarment = false
    @State private var publishToFeed = false
    @State private var postCaption = "오늘의 WEARy"

    private let analyzer: any OutfitAnalyzing = DemoOutfitAnalyzer()

    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.ink.ignoresSafeArea()
                switch phase {
                case .ready: readyView
                case .preview: previewView
                case .analyzing: analyzingView
                case .review: reviewView
                case .saved: savedView
                case .failed(let message): failedView(message)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(phase == .ready && cameraReadiness == .ready ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if phase != .ready && phase != .saved {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("처음부터") { reset() }
                            .foregroundStyle(.white)
                            .lightTextOutline()
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            phase = .failed("선택한 사진을 불러올 수 없어요. 다른 사진을 선택해 주세요.")
                            return
                        }
                        photoData = data
                        phase = .preview
                    } catch {
                        phase = .failed("사진을 불러오는 중 문제가 생겼어요. 다시 선택해 주세요.")
                    }
                }
            }
            .sheet(isPresented: $showingGarmentPicker) {
                OutfitGarmentPicker(garments: garments) { applyManualSelection($0) }
            }
            .sheet(isPresented: $showingNewGarment) { GarmentEditorView() }
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

    private var navigationTitle: String {
        switch phase {
        case .review: "매칭 확인"
        case .saved: "기록 완료"
        default: "착장 기록"
        }
    }

    private var readyView: some View {
        Group {
            switch cameraReadiness {
            case .checking:
                ProgressView("카메라 준비 중")
                    .tint(WEARyTheme.lime)
                    .foregroundStyle(.white)
                    .lightTextOutline()
            case .ready:
                OutfitCameraView(
                    onCapture: acceptPhoto,
                    onFailure: { cameraMessage = $0 }
                )
                .ignoresSafeArea(edges: .top)
            case .unavailable, .denied:
                cameraFallbackView
            }
        }
        .task {
            await prepareCameraIfNeeded()
        }
    }

    private var cameraFallbackView: some View {
        ScrollView {
            VStack(spacing: 26) {
                ZStack {
                    RoundedRectangle(cornerRadius: 36)
                        .stroke(WEARyTheme.lime, style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .frame(width: 220, height: 350)
                    Image(systemName: "figure.stand")
                        .font(.system(size: 135, weight: .ultraLight))
                        .foregroundStyle(WEARyTheme.surface.opacity(0.82))
                }
                VStack(spacing: 8) {
                    Text("오늘의 룩을 남겨보세요")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .lightTextOutline()
                    Text("전신이 프레임 안에 들어오면\n내 옷장에서 입은 옷을 찾아드려요.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.65))
                        .lightTextOutline()
                }
                VStack(spacing: 12) {
                    Button {
                        requestCamera()
                    } label: {
                        Label("카메라로 촬영", systemImage: "camera.fill")
                            .primaryCaptureButtonStyle()
                    }
                    .accessibilityIdentifier("capture.camera")
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label("사진 보관함에서 선택", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lightTextOutline()
                            .padding(.vertical, 10)
                    }
                    Button {
                        photoData = UIImage(named: "DemoOutfitLeather")?.jpegData(compressionQuality: 0.84)
                        phase = .preview
                    } label: {
                        Text("샘플 사진으로 체험")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lightTextOutline()
                            .padding(.vertical, 10)
                    }
                    .accessibilityIdentifier("capture.sample")
                }
                .padding(.horizontal, 28)
            }
            .padding(.top, 30)
            .padding(.bottom, 40)
            .foregroundStyle(.white)
        }
    }

    private var previewView: some View {
        VStack(spacing: 0) {
            OutfitPhotoPreview(photoData: photoData).frame(maxHeight: .infinity)
            VStack(spacing: 16) {
                DatePicker("착용 날짜", selection: $wornAt)
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                Button {
                    Task { await analyze() }
                } label: {
                    Label("내 옷장에서 찾기", systemImage: "sparkles")
                        .primaryCaptureButtonStyle()
                }
                .accessibilityIdentifier("capture.analyze")
            }
            .padding(22)
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 28) {
            ZStack {
                OutfitPhotoPreview(photoData: photoData)
                    .frame(width: 230, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .opacity(0.48)
                ProgressView().controlSize(.large).tint(WEARyTheme.lime)
            }
            VStack(spacing: 8) {
                Text("옷장에서 찾고 있어요")
                    .font(.title2.bold())
                    .lightTextOutline()
                Text("색상과 형태가 비슷한 옷을 비교하는 중")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    .lightTextOutline()
            }
        }
        .foregroundStyle(.white)
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    OutfitPhotoPreview(photoData: photoData)
                        .frame(width: 92, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI가 \(groups.count)개 아이템을 찾았어요")
                            .font(.headline)
                            .lightTextOutline()
                        Text("틀린 옷만 바꾸고 기록을 확정하세요.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.58))
                            .lightTextOutline()
                    }
                }
                ForEach(groups) { group in
                    MatchGroupCard(
                        group: group,
                        candidates: candidateGarments(for: group),
                        selectedGarment: garment(with: group.selectedGarmentID),
                        onSelect: { select($0, in: group.id) },
                        onChooseOther: {
                            editingGroupID = group.id
                            showingGarmentPicker = true
                        },
                        onExclude: { select(nil, in: group.id) }
                    )
                }
                HStack(spacing: 10) {
                    Button {
                        editingGroupID = nil
                        showingGarmentPicker = true
                    } label: {
                        Label("옷 직접 추가", systemImage: "plus")
                            .lightTextOutline()
                    }
                    Button {
                        showingNewGarment = true
                    } label: {
                        Label("새 옷 등록", systemImage: "hanger")
                            .lightTextOutline()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("커뮤니티에 공개", isOn: $publishToFeed)
                        .font(.subheadline.weight(.bold))
                        .tint(WEARyTheme.lime)
                        .lightTextOutline()
                    if publishToFeed {
                        TextField("오늘의 룩을 소개해 주세요", text: $postCaption, axis: .vertical)
                            .lightTextOutline()
                            .padding(12)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("개인 착장 기록은 기본적으로 나만 볼 수 있어요.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                        .lightTextOutline()
                }
                .padding(16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))

                Button(action: saveOutfit) {
                    Text("착장 기록하기 · \(selectedGarmentIDs.count)개")
                        .primaryCaptureButtonStyle()
                }
                .accessibilityIdentifier("capture.save")
                .disabled(selectedGarmentIDs.isEmpty)
                .opacity(selectedGarmentIDs.isEmpty ? 0.45 : 1)
            }
            .padding(18).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
    }

    private var savedView: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(WEARyTheme.ink)
                .frame(width: 82, height: 82)
                .background(WEARyTheme.lime, in: Circle())
            VStack(spacing: 7) {
                Text("오늘의 룩을 기록했어요")
                    .font(.title2.bold())
                    .lightTextOutline()
                Text("선택한 옷의 착용 데이터가 갱신됐어요.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.62))
                    .lightTextOutline()
            }
            Button("다른 착장 기록하기", action: reset)
                .buttonStyle(.borderedProminent)
                .tint(WEARyTheme.lime)
                .foregroundStyle(WEARyTheme.ink)
        }
        .foregroundStyle(.white)
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("분석하지 못했어요", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.white)
                .lightTextOutline()
        } description: {
            Text(message)
                .foregroundStyle(.white.opacity(0.65))
                .lightTextOutline()
        } actions: {
            Button("다시 시도") { phase = .preview }
                .buttonStyle(.borderedProminent)
                .tint(WEARyTheme.lime)
                .foregroundStyle(WEARyTheme.ink)
        }
    }

    @MainActor
    private func analyze() async {
        phase = .analyzing
        do {
            groups = try await analyzer.analyze(
                wardrobe: garments.map { GarmentSnapshot(id: $0.id, category: $0.category, name: $0.name) }
            )
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func garment(with id: UUID?) -> Garment? {
        guard let id else { return nil }
        return garments.first { $0.id == id }
    }

    private func candidateGarments(for group: DetectedGarmentGroup) -> [Garment] {
        group.candidateIDs.compactMap(garment(with:))
    }

    private func select(_ garment: Garment?, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].selectedGarmentID = garment?.id
    }

    private func applyManualSelection(_ garment: Garment) {
        if let editingGroupID {
            select(garment, in: editingGroupID)
        } else {
            groups.append(DetectedGarmentGroup(
                category: garment.category,
                candidateIDs: [garment.id],
                selectedGarmentID: garment.id,
                confidence: .none,
                source: .manual
            ))
        }
        showingGarmentPicker = false
    }

    private var selectedGarmentIDs: [UUID] {
        OutfitSelection.uniqueGarmentIDs(in: groups)
    }

    private func saveOutfit() {
        let outfit = Outfit(wornAt: wornAt, isPublished: publishToFeed, photoData: photoData)
        modelContext.insert(outfit)
        let selectedGarments = selectedGarmentIDs
            .compactMap(garment(with:))
            .sorted {
                if $0.category.outfitSortOrder == $1.category.outfitSortOrder { return $0.name < $1.name }
                return $0.category.outfitSortOrder < $1.category.outfitSortOrder
            }
        for (index, selectedGarment) in selectedGarments.enumerated() {
            let group = groups.first { $0.selectedGarmentID == selectedGarment.id }
            modelContext.insert(OutfitItem(
                garment: selectedGarment,
                outfit: outfit,
                source: group?.source ?? .manual,
                confidence: group?.confidence ?? .none,
                displayOrder: index
            ))
        }
        do {
            if publishToFeed {
                modelContext.insert(CommunityPost(
                    authorName: "나",
                    authorHandle: "my.weary",
                    authorInitials: "ME",
                    caption: postCaption.isEmpty ? "오늘의 WEARy" : postCaption,
                    tags: ["오늘의룩", "WEARy"],
                    accentHex: "C7F25B",
                    outfit: outfit
                ))
            }
            try modelContext.save()
            phase = .saved
        } catch {
            modelContext.delete(outfit)
            phase = .failed("기록을 저장하지 못했어요. 다시 시도해 주세요.")
        }
    }

    private func requestCamera() {
        Task {
            switch await CameraAccess.request() {
            case .ready:
                cameraReadiness = .ready
            case .unavailable:
                cameraReadiness = .unavailable
                cameraMessage = "이 기기에서는 카메라를 사용할 수 없어요. 사진 보관함이나 샘플 사진을 이용해 주세요."
            case .denied:
                cameraReadiness = .denied
                cameraMessage = "설정에서 WEARy의 카메라 접근을 허용한 뒤 다시 시도해 주세요."
            }
        }
    }

    private func prepareCameraIfNeeded() async {
        guard cameraReadiness == .checking else { return }
        switch await CameraAccess.request() {
        case .ready:
            cameraReadiness = .ready
        case .unavailable:
            cameraReadiness = .unavailable
        case .denied:
            cameraReadiness = .denied
        }
    }

    private func acceptPhoto(_ data: Data) {
        selectedPhoto = nil
        photoData = data
        phase = .preview
    }

    private func reset() {
        selectedPhoto = nil
        photoData = nil
        cameraMessage = nil
        wornAt = .now
        groups = []
        editingGroupID = nil
        publishToFeed = false
        postCaption = "오늘의 WEARy"
        phase = .ready
    }
}

private struct OutfitPhotoPreview: View {
    let photoData: Data?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "B7C9C3"), Color(hex: "879B94")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "figure.stand.dress")
                        .font(.system(size: 120, weight: .ultraLight))
                    Text("SAMPLE LOOK").font(.caption.weight(.black)).tracking(2)
                }
                .foregroundStyle(WEARyTheme.ink.opacity(0.75))
            }
        }
        .clipped()
    }
}

private struct MatchGroupCard: View {
    let group: DetectedGarmentGroup
    let candidates: [Garment]
    let selectedGarment: Garment?
    let onSelect: (Garment) -> Void
    let onChooseOther: () -> Void
    let onExclude: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(group.category.rawValue, systemImage: group.category.symbol)
                    .font(.headline)
                    .lightTextOutline()
                Spacer()
                Text(group.confidence == .high ? "AI 추천" : "비슷한 옷")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WEARyTheme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(group.confidence == .high ? WEARyTheme.lime : WEARyTheme.surface, in: Capsule())
            }
            if let selectedGarment {
                HStack(spacing: 12) {
                    GarmentArtwork(garment: selectedGarment, height: 74)
                        .frame(width: 74).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedGarment.brand.uppercased())
                            .font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55))
                            .lightTextOutline()
                        Text(selectedGarment.name)
                            .font(.subheadline.weight(.semibold))
                            .lightTextOutline()
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WEARyTheme.lime)
                }
            } else {
                Text("이 카테고리는 기록에서 제외했어요.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.58))
                    .lightTextOutline()
            }
            if candidates.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(candidates) { garment in
                            Button(garment.name) { onSelect(garment) }
                                .font(.caption.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(selectedGarment?.id == garment.id ? WEARyTheme.lime : Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(selectedGarment?.id == garment.id ? WEARyTheme.ink : .white)
                                .lightTextOutline(isActive: selectedGarment?.id != garment.id)
                        }
                    }
                }
            }
            HStack {
                Button("다른 옷 선택", action: onChooseOther)
                Spacer()
                Button("제외", action: onExclude)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            .lightTextOutline()
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct OutfitGarmentPicker: View {
    @Environment(\.dismiss) private var dismiss
    let garments: [Garment]
    let onSelect: (Garment) -> Void

    var body: some View {
        NavigationStack {
            List(garments) { garment in
                Button { onSelect(garment) } label: {
                    HStack(spacing: 12) {
                        GarmentArtwork(garment: garment, height: 58)
                            .frame(width: 58).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading) {
                            Text(garment.name).fontWeight(.semibold)
                            Text("\(garment.category.rawValue) · \(garment.brand)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("내 옷장에서 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

private extension View {
    func primaryCaptureButtonStyle() -> some View {
        font(.headline)
            .foregroundStyle(WEARyTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(WEARyTheme.lime, in: Capsule())
    }
}
