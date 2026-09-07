import SwiftData
import SwiftUI

struct MarketView: View {
    @Query(sort: \MarketListing.createdAt, order: .reverse) private var listings: [MarketListing]
    @State private var showingSellFlow = false
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()
                if listings.isEmpty {
                    ContentUnavailableView(
                        "등록된 옷이 없어요",
                        systemImage: "bag.badge.plus",
                        description: Text("입지 않는 옷을 다음 옷장으로 보내보세요.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("옷장에서 다음 옷장으로")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(listings) { listing in
                                    NavigationLink(value: listing) {
                                        MarketListingCard(listing: listing)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("마켓")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("판매") { showingSellFlow = true }.fontWeight(.bold)
                }
            }
            .navigationDestination(for: MarketListing.self) { listing in
                MarketListingDetailView(listing: listing)
            }
            .sheet(isPresented: $showingSellFlow) { SellGarmentPicker() }
        }
    }
}

private struct MarketListingCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var listing: MarketListing

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            MarketArtwork(listing: listing).frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) {
                    Text(listing.status.rawValue)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(9)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        listing.isLiked.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: listing.isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(listing.isLiked ? WEARyTheme.coral : WEARyTheme.ink)
                            .padding(9).background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(8)
                }
            Text(listing.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(listing.price.formatted(.currency(code: "KRW").precision(.fractionLength(0))))
                .font(.headline)
            Text("\(listing.size) · \(listing.condition.rawValue)")
                .font(.caption2).foregroundStyle(WEARyTheme.secondaryInk).lineLimit(1)
        }
        .padding(10)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct MarketArtwork: View {
    let listing: MarketListing

    var body: some View {
        ZStack {
            Color(hex: listing.accentHex).opacity(0.78)
            Circle().fill(.white.opacity(0.18)).frame(width: 170).offset(x: 55, y: -55)
            if let garment = listing.garment {
                GarmentCutoutThumbnail(garment: garment)
                    .frame(width: 135, height: 150).padding(12)
            } else {
                Image(systemName: "hanger").font(.system(size: 54, weight: .light))
            }
        }
        .clipped()
    }
}

private struct MarketListingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var listing: MarketListing
    @State private var showingChat = false
    @State private var showingRequestConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MarketArtwork(listing: listing).frame(height: 410).clipped()
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(listing.sellerName).font(.caption.weight(.bold)).foregroundStyle(WEARyTheme.coral)
                            Text(listing.title).font(.title2.bold())
                        }
                        Spacer()
                        Text(listing.status.rawValue)
                            .font(.caption.weight(.bold)).padding(8)
                            .background(WEARyTheme.lime, in: Capsule())
                    }
                    Text(listing.price.formatted(.currency(code: "KRW").precision(.fractionLength(0))))
                        .font(.title.bold())
                    HStack(spacing: 8) {
                        detailPill("사이즈", listing.size)
                        detailPill("상태", listing.condition.rawValue)
                        if let count = listing.garment?.wearCount { detailPill("착용", "\(count)회") }
                    }
                    Text(listing.detailText).font(.body).foregroundStyle(WEARyTheme.secondaryInk)
                    if let garment = listing.garment {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("옷장 데이터 인증").font(.headline)
                            Text("구매가 \(garment.purchasePrice?.formatted() ?? "미입력")원 · 마지막 착용 \(garment.lastWornAt?.formatted(date: .abbreviated, time: .omitted) ?? "기록 없음")")
                                .font(.subheadline).foregroundStyle(WEARyTheme.secondaryInk)
                        }
                        .padding(16).background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    HStack(spacing: 10) {
                        Button { showingChat = true } label: {
                            Label("채팅", systemImage: "bubble.left.and.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            listing.status = .reserved
                            try? modelContext.save()
                            showingRequestConfirmation = true
                        } label: {
                            Text("구매 요청").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(WEARyTheme.ink)
                        .disabled(listing.status != .active)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .background(WEARyTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingChat) { MockChatView(sellerName: listing.sellerName) }
        .alert("구매를 요청했어요", isPresented: $showingRequestConfirmation) {
            Button("확인", role: .cancel) { }
        } message: { Text("판매자가 확인하면 채팅으로 알려드릴게요.") }
    }

    private func detailPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(WEARyTheme.secondaryInk)
            Text(value).font(.caption.weight(.bold)).lineLimit(1)
        }
        .padding(10).background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CreateListingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let garment: Garment
    @State private var title: String
    @State private var detailText: String
    @State private var price: String
    @State private var condition: ListingCondition = .excellent

    init(garment: Garment) {
        self.garment = garment
        _title = State(initialValue: garment.name)
        _detailText = State(initialValue: "깨끗하게 보관한 \(garment.brand) \(garment.name)입니다. 실제 착용은 \(garment.wearCount)회예요.")
        _price = State(initialValue: String((garment.purchasePrice ?? 50_000) / 2))
    }

    var body: some View {
        Form {
            Section("판매할 옷") {
                HStack(spacing: 12) {
                    GarmentCutoutThumbnail(garment: garment).frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Text(garment.name).fontWeight(.semibold)
                        Text("\(garment.brand) · \(garment.size)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("판매 정보") {
                TextField("상품명", text: $title)
                TextField("판매 가격", text: $price).keyboardType(.numberPad)
                Picker("상품 상태", selection: $condition) {
                    ForEach(ListingCondition.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("상품 설명", text: $detailText, axis: .vertical).lineLimit(4...8)
            }
            Section {
                Label("착용 \(garment.wearCount)회 · 구매 정보와 옷장 사진으로 작성했어요", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
            }
        }
        .scrollContentBackground(.hidden).background(WEARyTheme.canvas)
        .navigationTitle("판매 글 만들기").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("등록", action: save).fontWeight(.bold)
                    .disabled(title.isEmpty || Int(price) == nil)
            }
        }
    }

    private func save() {
        modelContext.insert(MarketListing(
            sellerName: "나의 옷장", title: title, detailText: detailText,
            price: Int(price) ?? 0, originalPrice: garment.purchasePrice,
            size: garment.size, condition: condition, accentHex: garment.colorHex, garment: garment
        ))
        garment.status = .selling
        try? modelContext.save()
        dismiss()
    }
}

private struct SellGarmentPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Garment.createdAt, order: .reverse) private var garments: [Garment]

    var body: some View {
        NavigationStack {
            List(garments) { garment in
                NavigationLink {
                    CreateListingView(garment: garment)
                } label: {
                    HStack(spacing: 12) {
                        GarmentCutoutThumbnail(garment: garment).frame(width: 54, height: 54)
                        VStack(alignment: .leading) {
                            Text(garment.name).fontWeight(.semibold)
                            Text("\(garment.wearCount)회 착용 · \(garment.status.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("판매할 옷 선택").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

private struct MockChatView: View {
    @Environment(\.dismiss) private var dismiss
    let sellerName: String
    @State private var messages = ["안녕하세요! 아직 판매 중인가요?", "네, 상태도 아주 좋아요 🙂"]
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            Text(message)
                                .font(.subheadline).padding(12)
                                .background(index.isMultiple(of: 2) ? WEARyTheme.lime : WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                                .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 2) ? .trailing : .leading)
                        }
                    }.padding()
                }
                HStack {
                    TextField("메시지", text: $input).textFieldStyle(.roundedBorder)
                    Button("전송") {
                        guard !input.isEmpty else { return }
                        messages.append(input); input = ""
                    }.fontWeight(.bold)
                }.padding()
            }
            .background(WEARyTheme.canvas)
            .navigationTitle(sellerName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
