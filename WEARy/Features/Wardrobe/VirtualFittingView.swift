import SwiftUI
import PhotosUI
import Combine

/// Normalized placement in the photo, not screen coordinates or physical size.
struct FittingOverlayPlacement: Equatable {
    private(set) var x = 0.5
    private(set) var y = 0.42
    private(set) var scale = 0.65
    mutating func update(x: Double? = nil, y: Double? = nil, scale: Double? = nil) {
        if let x, x.isFinite { self.x = min(max(x, 0), 1) }
        if let y, y.isFinite { self.y = min(max(y, 0), 1) }
        if let scale, scale.isFinite { self.scale = min(max(scale, 0.2), 1) }
    }
    mutating func reset() { self = Self() }
    static func automatic(rect: CGRect) -> Self {
        var result = Self()
        result.update(x: rect.midX, y: rect.midY, scale: rect.width)
        return result
    }
}

@MainActor
final class FittingPhotoModel: ObservableObject {
    @Published private(set) var photo: UIImage?
    @Published private(set) var photoSize = CGSize.zero
    @Published private(set) var isLoading = false
    @Published private(set) var isSample = false
    @Published private(set) var outcome: FittingPhotoOutcome?
    @Published private(set) var errorMessage: String?
    @Published var placement = FittingOverlayPlacement()
    @Published var showsOverlay = false
    private var initialPlacement = FittingOverlayPlacement()
    private var gate = FittingPhotoRequestGate()

    var message: String {
        if isLoading { return "사진을 불러와 상반신 위치를 분석하고 있어요." }
        if let errorMessage { return errorMessage }
        return outcome?.message ?? "한 명의 양쪽 어깨가 보이는 사진을 선택해 주세요. 상반신만 나와도 괜찮아요."
    }

    func load(isSample: Bool = false,
              analyze: @escaping @Sendable (Data) throws -> FittingPhotoResult = FittingPhotoProcessor.process,
              dataLoader: () async throws -> Data?) async {
        let token = gate.begin()
        resetContent()
        self.isSample = isSample
        isLoading = true
        do {
            guard let data = try await dataLoader() else { throw FittingPhotoError.invalidImage }
            try Task.checkCancellation()
            guard gate.accepts(token) else { return }
            let result = try await Task.detached(priority: .userInitiated) { try analyze(data) }.value
            guard gate.accepts(token), !Task.isCancelled else { return }
            guard let photo = UIImage(data: result.data) else { throw FittingPhotoError.invalidImage }
            self.photo = photo
            photoSize = result.size
            outcome = result.outcome
            if let rect = result.rect, result.outcome == .placed {
                initialPlacement = .automatic(rect: rect)
                placement = initialPlacement
                showsOverlay = true
            }
            isLoading = false
        } catch {
            guard gate.accepts(token), !Task.isCancelled else { return }
            isLoading = false
            errorMessage = "사진을 읽지 못했어요. 다른 사진을 선택해 주세요."
        }
    }

    func resetPlacement() { placement = initialPlacement }
    func enableManual() { guard photo != nil else { return }; showsOverlay = true }
    func clear() { _ = gate.begin(); resetContent() }
    private func resetContent() {
        photo = nil; photoSize = .zero; outcome = nil; errorMessage = nil
        isLoading = false; isSample = false; showsOverlay = false
        placement.reset(); initialPlacement = placement
    }
}

struct VirtualFittingView: View {
    @Environment(\.dismiss) private var dismiss
    let garmentName: String
    let image: UIImage
    @StateObject private var model = FittingPhotoModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sampleTask: Task<Void, Never>?
    @State private var dragOrigin: FittingOverlayPlacement?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("사진 기반 피팅 · 실험").font(.headline).accessibilityIdentifier("fitting.stage")
                    Text("사진을 선택하면 상반신 위치를 찾아 상의 이미지를 자동 배치해요. 자연스러운 옷 합성·Jev 연결은 아직 없으며 실제 사이즈나 핏을 판단할 수 없어요.")
                        .font(.caption)
                    preview
                    Text(garmentName).font(.headline)
                    Text(model.message).font(.caption).accessibilityIdentifier("fitting.status")
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("내 사진 선택", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fitting.selectPhoto")
                    HStack {
                        Button("샘플로 체험") {
                            selectedPhoto = nil
                            sampleTask?.cancel()
                            let data = UIImage(named: "DemoOutfitLeather")?.pngData()
                            sampleTask = Task { await model.load(isSample: true) { data } }
                        }.accessibilityIdentifier("fitting.sample")
                        Button("사진 지우기") {
                            selectedPhoto = nil
                            sampleTask?.cancel()
                            model.clear()
                        }.accessibilityIdentifier("fitting.clear")
                    }.buttonStyle(.bordered)
                    if model.photo != nil && !model.showsOverlay {
                        Button("수동으로 배치") { model.enableManual() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("fitting.manual")
                    }
                    if model.photo != nil && model.showsOverlay {
                        Text("배치된 옷을 끌거나 아래 조절기로 보정하세요.").font(.caption)
                        adjustment("크기", value: Binding(get: { model.placement.scale }, set: { model.placement.update(scale: $0) }), range: 0.2...1, id: "fitting.scale")
                        adjustment("가로 위치", value: Binding(get: { model.placement.x }, set: { model.placement.update(x: $0) }), range: 0...1, id: "fitting.x")
                        adjustment("세로 위치", value: Binding(get: { model.placement.y }, set: { model.placement.update(y: $0) }), range: 0...1, id: "fitting.y")
                        Button("위치·크기 초기화") { model.resetPlacement(); dragOrigin = nil }
                            .accessibilityIdentifier("fitting.reset")
                    }
                    Text("사진은 이 화면의 메모리에서만 처리하며 저장·서버 전송·착용 횟수 반영을 하지 않아요. 선택한 사진의 방향을 유지하며 추가 좌우 반전을 하지 않아요. 배경이 제거되지 않은 옷은 배경도 함께 표시돼요.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(WEARyTheme.canvas)
            .navigationTitle("가상 피팅 · 실험")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("완료") { dismiss() }.accessibilityIdentifier("fitting.close") }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                sampleTask?.cancel()
                await model.load { try await selectedPhoto.loadTransferable(type: Data.self) }
            }
            .onDisappear { sampleTask?.cancel(); model.clear() }
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let photo = model.photo,
                   let frame = FittingBodyGeometry.photoFrame(imageSize: model.photoSize, viewport: proxy.size) {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    if model.showsOverlay {
                        let width = frame.width * model.placement.scale
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: width, height: width * image.size.height / max(image.size.width, 1))
                            .position(x: frame.minX + frame.width * model.placement.x,
                                      y: frame.minY + frame.height * model.placement.y)
                            .gesture(DragGesture().onChanged { value in
                                let origin = dragOrigin ?? model.placement
                                if dragOrigin == nil { dragOrigin = origin }
                                model.placement.update(x: origin.x + value.translation.width / max(frame.width, 1),
                                                       y: origin.y + value.translation.height / max(frame.height, 1))
                            }.onEnded { _ in dragOrigin = nil })
                            .accessibilityLabel("선택한 옷 겹쳐보기")
                            .accessibilityIdentifier("fitting.overlay")
                    }
                } else {
                    Image(systemName: "person.crop.rectangle").font(.system(size: 80)).foregroundStyle(.gray)
                }
                if model.isLoading { ProgressView().tint(.white).accessibilityIdentifier("fitting.loading") }
                VStack {
                    Text(model.isSample ? "샘플 사진 · 합성 아님" : "사진 기반 · 합성 아님")
                        .font(.caption.weight(.bold)).padding(8)
                        .background(.black.opacity(0.7), in: Capsule()).foregroundStyle(.white)
                    Spacer()
                }.padding(12).allowsHitTesting(false)
            }.clipped().clipShape(RoundedRectangle(cornerRadius: 24))
        }.frame(height: 330)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title).accessibilityIdentifier(id)
        }
    }
}
