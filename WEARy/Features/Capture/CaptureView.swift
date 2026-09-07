import PhotosUI
import SwiftData
import SwiftUI

struct CaptureView: View {
    private enum Phase: Equatable {
        case ready, preview, analyzing, review, saved
        case failed(String)
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Garment.createdAt) private var garments: [Garment]
    @State private var phase: Phase = .ready
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var wornAt = Date.now
    @State private var groups: [DetectedGarmentGroup] = []
    @State private var editingGroupID: UUID?
    @State private var showingGarmentPicker = false
    @State private var showingNewGarment = false

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
            .toolbar {
                if phase != .ready && phase != .saved {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("처음부터") { reset() }.foregroundStyle(.white)
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photoData = data
                        phase = .preview
                    }
                }
            }
            .sheet(isPresented: $showingGarmentPicker) {
                OutfitGarmentPicker(garments: garments) { applyManualSelection($0) }
            }
            .sheet(isPresented: $showingNewGarment) { GarmentEditorView() }
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
                    Text("전신이 프레임 안에 들어오면\n내 옷장에서 입은 옷을 찾아드려요.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.65))
                }
                VStack(spacing: 12) {
                    PhotosPicker(
                        "사진 보관함에서 선택",
                        selection: $selectedPhoto,
                        matching: .images
                    )
                    .primaryCaptureButtonStyle()
                    Button {
                        photoData = nil
                        phase = .preview
                    } label: {
                        Text("샘플 사진으로 체험")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                    }
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
                Text("옷장에서 찾고 있어요").font(.title2.bold())
                Text("색상과 형태가 비슷한 옷을 비교하는 중")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
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
                        Text("AI가 \(groups.count)개 아이템을 찾았어요").font(.headline)
                        Text("틀린 옷만 바꾸고 기록을 확정하세요.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.58))
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
                    } label: { Label("옷 직접 추가", systemImage: "plus") }
                    Button {
                        showingNewGarment = true
                    } label: { Label("새 옷 등록", systemImage: "hanger") }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)

                Button(action: saveOutfit) {
                    Text("착장 기록하기 · \(selectedGarmentIDs.count)개")
                        .primaryCaptureButtonStyle()
                }
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
                Text("오늘의 룩을 기록했어요").font(.title2.bold())
                Text("선택한 옷의 착용 데이터가 갱신됐어요.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.62))
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
        } description: {
            Text(message).foregroundStyle(.white.opacity(0.65))
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
        let outfit = Outfit(wornAt: wornAt, photoData: photoData)
        modelContext.insert(outfit)
        for garmentID in selectedGarmentIDs {
            guard let garment = garment(with: garmentID) else { continue }
            let group = groups.first { $0.selectedGarmentID == garmentID }
            modelContext.insert(OutfitItem(
                garment: garment,
                outfit: outfit,
                source: group?.source ?? .manual,
                confidence: group?.confidence ?? .none
            ))
        }
        do {
            try modelContext.save()
            phase = .saved
        } catch {
            modelContext.delete(outfit)
            phase = .failed("기록을 저장하지 못했어요. 다시 시도해 주세요.")
        }
    }

    private func reset() {
        selectedPhoto = nil
        photoData = nil
        wornAt = .now
        groups = []
        editingGroupID = nil
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
                Label(group.category.rawValue, systemImage: group.category.symbol).font(.headline)
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
                        Text(selectedGarment.name).font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WEARyTheme.lime)
                }
            } else {
                Text("이 카테고리는 기록에서 제외했어요.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.58))
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
