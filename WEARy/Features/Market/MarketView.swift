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
            Label("채팅 \(listing.displayedChatCount)명", systemImage: "bubble.left.and.bubble.right")
                .font(.caption2)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .padding(10)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct MarketArtwork: View {
    let listing: MarketListing
    var usesGalleryCover = true

    var body: some View {
        ZStack {
            Color(hex: listing.accentHex).opacity(0.78)
            Circle().fill(.white.opacity(0.18)).frame(width: 170).offset(x: 55, y: -55)
            if usesGalleryCover,
               let data = listing.galleryImages.first,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let data = listing.garmentCutoutImageDataSnapshot,
                      let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 135, height: 150).padding(12)
            } else {
                Image(systemName: listing.hasWardrobeSnapshot ? listing.garmentCategorySnapshot.symbol : "hanger")
                    .font(.system(size: 54, weight: .light))
            }
        }
        .clipped()
    }
}

private struct MarketListingGallery: View {
    let listing: MarketListing

    var body: some View {
        TabView {
            MarketArtwork(listing: listing, usesGalleryCover: false)
                .accessibilityLabel("기본 옷 사진")

            ForEach(Array(listing.galleryImages.enumerated()), id: \.offset) { index, data in
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .accessibilityLabel("판매 사진 \(index + 1)")
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: listing.galleryImages.isEmpty ? .never : .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(hex: listing.accentHex).opacity(0.78))
        .accessibilityIdentifier("market.photoGallery")
    }
}

private struct MarketListingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var listing: MarketListing
    @State private var showingChat = false
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MarketListingGallery(listing: listing).frame(height: 410).clipped()
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(listing.sellerName).font(.caption.weight(.bold)).foregroundStyle(WEARyTheme.coral)
                            HStack(spacing: 7) {
                                Text(listing.title).font(.title2.bold())
                                if listing.showsWardrobeVerification, listing.hasWardrobeSnapshot {
                                    Image(systemName: "star.fill")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(Color(red: 0.88, green: 0.64, blue: 0.08))
                                        .accessibilityLabel("옷장 데이터 인증")
                                        .accessibilityIdentifier("market.verifiedBadge")
                                }
                            }
                        }
                        Spacer()
                        Text(listing.status.rawValue)
                            .font(.caption.weight(.bold)).padding(8)
                            .background(WEARyTheme.lime, in: Capsule())
                    }
                    HStack(spacing: 10) {
                        Text(listing.price.formatted(.currency(code: "KRW").precision(.fractionLength(0))))
                            .font(.title.bold())
                        if let priceChange = listing.priceChange {
                            Text(priceChangeText(priceChange))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(priceChange > 0 ? Color.red : Color.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("가격 변동 \(priceChangeText(priceChange))원")
                                .accessibilityIdentifier("market.priceChange")
                        }
                    }
                    HStack(spacing: 8) {
                        detailPill("사이즈", listing.size)
                        detailPill("상태", listing.condition.rawValue)
                        if let count = listing.verificationWearCount { detailPill("착용", "\(count)회") }
                    }
                    Text(listing.detailText).font(.body).foregroundStyle(WEARyTheme.secondaryInk)
                    if let meetingPlace = listing.meetingPlaceSelection {
                        MeetingPlaceMapCard(selection: meetingPlace)
                    } else {
                        Label(listing.displayedMeetingPlace, systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if listing.showsWardrobeVerification, listing.hasWardrobeSnapshot {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("옷장 데이터 인증").font(.headline)
                            Text("구매가 \(listing.verificationPurchasePrice?.formatted() ?? "미입력")원 · 마지막 착용 \(listing.verificationLastWornAt?.formatted(date: .abbreviated, time: .omitted) ?? "기록 없음")")
                                .font(.subheadline).foregroundStyle(WEARyTheme.secondaryInk)
                        }
                        .padding(16).background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if listing.isOwnedByCurrentUser {
                        ownerActions
                    } else {
                        buyerActions
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .background(WEARyTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if listing.isOwnedByCurrentUser {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("수정", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("게시물 삭제", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("market.ownerMenu")
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            if listing.isOwnedByCurrentUser {
                SellerChatListView(listing: listing)
            } else {
                MockChatView(sellerName: listing.sellerName)
            }
        }
        .sheet(isPresented: $showingEditor) { EditListingView(listing: listing) }
        .confirmationDialog("이 매물을 삭제할까요?", isPresented: $showingDeleteConfirmation) {
            Button("삭제", role: .destructive) { deleteListing() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("마켓 게시물만 삭제되고 옷은 내 옷장에 남습니다.")
        }
    }

    private var ownerActions: some View {
        HStack(spacing: 10) {
            Button {
                listing.isLiked.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: listing.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(listing.isLiked ? WEARyTheme.coral : WEARyTheme.ink)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(listing.isLiked ? "관심 해제" : "관심")
            .accessibilityIdentifier("market.ownerLike")

            Button {
                showingChat = true
            } label: {
                Label("채팅하기 · \(listing.displayedChatCount)명", systemImage: "bubble.left.and.bubble.right.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WEARyTheme.ink)
            .accessibilityIdentifier("market.ownerChat")
        }
    }

    private var buyerActions: some View {
        HStack(spacing: 10) {
            Button {
                listing.isLiked.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: listing.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(listing.isLiked ? WEARyTheme.coral : WEARyTheme.ink)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(listing.isLiked ? "관심 해제" : "관심")
            .accessibilityIdentifier("market.buyerLike")

            Button {
                showingChat = true
            } label: {
                Label("채팅하기", systemImage: "bubble.left.and.bubble.right.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WEARyTheme.ink)
            .accessibilityIdentifier("market.buyerChat")
        }
    }

    private func priceChangeText(_ change: Int) -> String {
        let sign = change > 0 ? "+" : "-"
        return "\(sign)\(abs(change).formatted())"
    }

    private func deleteListing() {
        if let garment = listing.sourceGarment(in: modelContext), garment.status == .selling {
            garment.status = .active
        }
        modelContext.delete(listing)
        try? modelContext.save()
        dismiss()
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
    @EnvironmentObject private var authentication: AuthenticationStore
    let garment: Garment
    @State private var title: String
    @State private var detailText: String
    @State private var price: String
    @State private var meetingPlace = ""
    @State private var meetingAddress = ""
    @State private var meetingLatitude: Double?
    @State private var meetingLongitude: Double?
    @State private var showingPlacePicker = false
    @State private var condition: ListingCondition = .excellent
    @State private var galleryImages: [Data] = []
    @State private var showsWardrobeVerification = false

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
            Section("판매 사진") {
                MarketPhotoEditorView(images: $galleryImages)
            }
            Section {
                TextField("상품명", text: $title)
                TextField("판매 가격", text: $price).keyboardType(.numberPad)
                Picker("상품 상태", selection: $condition) {
                    ForEach(ListingCondition.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("상품 설명을 직접 작성해 주세요", text: $detailText, axis: .vertical)
                    .lineLimit(4...8)
                meetingPlaceButton
                Toggle("옷장 데이터 인증 공개", isOn: $showsWardrobeVerification)
                    .accessibilityIdentifier("market.createVerification")
            } header: {
                Text("판매 정보")
            } footer: {
                Text("설명과 만날 장소는 등록 후에도 수정할 수 있어요.")
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
        .sheet(isPresented: $showingPlacePicker) {
            MeetingPlacePickerView(initialSelection: selectedMeetingPlace, onSelect: applyMeetingPlace)
        }
    }

    private var meetingPlaceButton: some View {
        Button {
            showingPlacePicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meetingPlace.isEmpty ? "지도에서 만날 장소 선택" : meetingPlace)
                        .foregroundStyle(WEARyTheme.ink)
                    if !meetingAddress.isEmpty {
                        Text(meetingAddress)
                            .font(.caption)
                            .foregroundStyle(WEARyTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "map")
            }
        }
        .accessibilityIdentifier("market.createPlace")
    }

    private var selectedMeetingPlace: MeetingPlaceSelection? {
        guard let meetingLatitude, let meetingLongitude else { return nil }
        return MeetingPlaceSelection(
            name: meetingPlace,
            address: meetingAddress,
            latitude: meetingLatitude,
            longitude: meetingLongitude
        )
    }

    private func applyMeetingPlace(_ selection: MeetingPlaceSelection) {
        meetingPlace = selection.name
        meetingAddress = selection.address
        meetingLatitude = selection.latitude
        meetingLongitude = selection.longitude
    }

    private func save() {
        modelContext.insert(MarketListing(
            sellerName: authentication.displayName, title: title, detailText: detailText,
            price: Int(price) ?? 0, originalPrice: garment.purchasePrice,
            size: garment.size, condition: condition, accentHex: garment.colorHex,
            meetingPlace: meetingPlace, meetingAddress: meetingAddress,
            meetingLatitude: meetingLatitude, meetingLongitude: meetingLongitude,
            chatCount: 0, galleryImages: galleryImages,
            showsWardrobeVerification: showsWardrobeVerification, garment: garment,
            isOwnedByCurrentUser: true
        ))
        garment.status = .selling
        try? modelContext.save()
        dismiss()
    }
}

private struct EditListingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let listing: MarketListing
    @State private var title: String
    @State private var detailText: String
    @State private var priceText: String
    @State private var meetingPlace: String
    @State private var meetingAddress: String
    @State private var meetingLatitude: Double?
    @State private var meetingLongitude: Double?
    @State private var showingPlacePicker = false
    @State private var condition: ListingCondition
    @State private var status: ListingStatus
    @State private var galleryImages: [Data]
    @State private var showsWardrobeVerification: Bool
    @State private var showingSoldConfirmation = false

    init(listing: MarketListing) {
        self.listing = listing
        _title = State(initialValue: listing.title)
        _detailText = State(initialValue: listing.detailText)
        _priceText = State(initialValue: String(listing.price))
        _meetingPlace = State(initialValue: listing.meetingPlace ?? "")
        _meetingAddress = State(initialValue: listing.meetingAddress ?? "")
        _meetingLatitude = State(initialValue: listing.meetingLatitude)
        _meetingLongitude = State(initialValue: listing.meetingLongitude)
        _condition = State(initialValue: listing.condition)
        _status = State(initialValue: listing.status)
        _galleryImages = State(initialValue: listing.galleryImages)
        _showsWardrobeVerification = State(initialValue: listing.showsWardrobeVerification)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("판매 사진") {
                    MarketPhotoEditorView(images: $galleryImages)
                }
                Section("판매 정보") {
                    TextField("상품명", text: $title)
                    Picker("상품 상태", selection: $condition) {
                        ForEach(ListingCondition.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("거래 상태", selection: $status) {
                        ForEach(ListingStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("상품 설명", text: $detailText, axis: .vertical)
                        .lineLimit(4...8)
                    meetingPlaceButton
                    Toggle("옷장 데이터 인증 공개", isOn: $showsWardrobeVerification)
                        .accessibilityIdentifier("market.editVerification")
                }

                Section {
                    TextField("판매 가격", text: $priceText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("market.priceInput")
                } header: {
                    Text("가격 조정")
                } footer: {
                    Text("현재 가격 \(listing.price.formatted())원 · 변경하면 직전 가격과의 차이를 표시해요.")
                }

                Section {
                    Button(role: .destructive) {
                        showingSoldConfirmation = true
                    } label: {
                        Label(
                            listing.status == .sold ? "판매 완료된 매물" : "판매완료",
                            systemImage: "checkmark.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(listing.status == .sold)
                    .accessibilityIdentifier("market.editMarkSold")
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle("수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .fontWeight(.bold)
                        .disabled(
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            (Int(priceText) ?? 0) <= 0
                        )
                        .accessibilityIdentifier("market.saveEdit")
                }
            }
            .confirmationDialog("판매완료로 변경할까요?", isPresented: $showingSoldConfirmation) {
                Button("판매완료", role: .destructive, action: markAsSold)
                Button("취소", role: .cancel) { }
            } message: {
                Text("마켓에서 판매 완료 상태로 표시됩니다.")
            }
            .sheet(isPresented: $showingPlacePicker) {
                MeetingPlacePickerView(initialSelection: selectedMeetingPlace, onSelect: applyMeetingPlace)
            }
        }
    }

    private var meetingPlaceButton: some View {
        Button {
            showingPlacePicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meetingPlace.isEmpty ? "지도에서 만날 장소 선택" : meetingPlace)
                        .foregroundStyle(WEARyTheme.ink)
                    if !meetingAddress.isEmpty {
                        Text(meetingAddress)
                            .font(.caption)
                            .foregroundStyle(WEARyTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "map")
            }
        }
        .accessibilityIdentifier("market.editPlace")
    }

    private var selectedMeetingPlace: MeetingPlaceSelection? {
        guard let meetingLatitude, let meetingLongitude else { return nil }
        return MeetingPlaceSelection(
            name: meetingPlace,
            address: meetingAddress,
            latitude: meetingLatitude,
            longitude: meetingLongitude
        )
    }

    private func applyMeetingPlace(_ selection: MeetingPlaceSelection) {
        meetingPlace = selection.name
        meetingAddress = selection.address
        meetingLatitude = selection.latitude
        meetingLongitude = selection.longitude
    }

    private func save() {
        guard let newPrice = Int(priceText), newPrice > 0 else { return }
        listing.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        listing.updatePrice(to: newPrice)
        listing.condition = condition
        listing.status = status
        listing.sourceGarment(in: modelContext)?.status = status == .sold ? .sold : .selling
        listing.detailText = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        listing.meetingPlace = meetingPlace.trimmingCharacters(in: .whitespacesAndNewlines)
        listing.meetingAddress = meetingAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        listing.meetingLatitude = meetingLatitude
        listing.meetingLongitude = meetingLongitude
        listing.updateGalleryImages(galleryImages)
        listing.showsWardrobeVerification = showsWardrobeVerification
        try? modelContext.save()
        dismiss()
    }

    private func markAsSold() {
        listing.status = .sold
        listing.sourceGarment(in: modelContext)?.status = .sold
        try? modelContext.save()
        dismiss()
    }
}

private struct SellerChatListView: View {
    @Environment(\.dismiss) private var dismiss
    let listing: MarketListing
    @State private var selectedBuyer: MockBuyer?

    private let buyers = [
        MockBuyer(name: "채원", handle: "chae.closet", message: "오늘 저녁에 거래 가능할까요?", initials: "CW"),
        MockBuyer(name: "준호", handle: "joon.fit", message: "실측 사이즈가 궁금해요!", initials: "JH"),
        MockBuyer(name: "수빈", handle: "subin.archive", message: "가격 조정 가능할까요?", initials: "SB"),
        MockBuyer(name: "유진", handle: "yujin.daily", message: "아직 판매 중인가요?", initials: "YJ"),
        MockBuyer(name: "태오", handle: "taeo.look", message: "주말에 직거래하고 싶어요.", initials: "TO"),
    ]

    private var visibleBuyers: [MockBuyer] {
        Array(buyers.prefix(listing.displayedChatCount))
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleBuyers.isEmpty {
                    ContentUnavailableView(
                        "아직 채팅이 없어요",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("구매 희망자의 메시지가 오면 이곳에 표시됩니다.")
                    )
                } else {
                    List(visibleBuyers) { buyer in
                        Button {
                            selectedBuyer = buyer
                        } label: {
                            HStack(spacing: 12) {
                                Text(buyer.initials)
                                    .font(.caption.weight(.black))
                                    .frame(width: 44, height: 44)
                                    .background(WEARyTheme.lime, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(buyer.name).fontWeight(.semibold)
                                    Text(buyer.message)
                                        .font(.caption)
                                        .foregroundStyle(WEARyTheme.secondaryInk)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                    .background(WEARyTheme.canvas)
                }
            }
            .navigationTitle("채팅 \(listing.displayedChatCount)명")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(item: $selectedBuyer) { buyer in
                MockChatView(sellerName: buyer.name)
            }
        }
    }
}

private struct MockBuyer: Identifiable {
    let name: String
    let handle: String
    let message: String
    let initials: String

    var id: String { handle }
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
