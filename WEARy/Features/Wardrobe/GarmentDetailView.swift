import SwiftData
import SwiftUI

struct GarmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let garment: Garment
    @State private var showingDeleteConfirmation = false
    @State private var showingEditor = false
    @State private var showingListingEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GarmentArtwork(garment: garment, height: 340)
                    .overlay(alignment: .bottomLeading) {
                        Text(garment.category.rawValue)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(WEARyTheme.lime, in: Capsule())
                            .padding(18)
                    }

                VStack(alignment: .leading, spacing: 24) {
                    identitySection
                    metricsSection
                    informationSection
                    historySection
                    statusSection
                    sellButton
                    deleteButton
                }
                .padding(20)
            }
        }
        .background(WEARyTheme.canvas)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("수정") { showingEditor = true }
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingEditor) {
            GarmentEditorView(garment: garment)
        }
        .sheet(isPresented: $showingListingEditor) {
            NavigationStack { CreateListingView(garment: garment) }
        }
        .confirmationDialog(
            "이 옷을 삭제할까요?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                modelContext.delete(garment)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("연결된 샘플 착장 기록도 함께 삭제됩니다.")
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(garment.brand.isEmpty ? "BRAND NOT SET" : garment.brand.uppercased())
                .font(.caption.weight(.black))
                .tracking(1.4)
                .foregroundStyle(WEARyTheme.coral)
            Text(garment.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("\(garment.colorName) · \(garment.season)")
                .font(.subheadline)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
    }

    private var metricsSection: some View {
        HStack(spacing: 10) {
            MetricPill(value: "\(garment.wearCount)회", label: "총 착용")
            MetricPill(value: "\(garment.wearDayCount)일", label: "착용일")
            MetricPill(value: costPerWearText, label: "1회 비용")
        }
    }

    private var informationSection: some View {
        VStack(spacing: 0) {
            informationRow("사이즈", value: garment.size.isEmpty ? "미입력" : garment.size)
            Divider()
            informationRow("구매 가격", value: priceText)
            Divider()
            informationRow("구매일", value: purchaseDateText)
            Divider()
            informationRow("마지막 착용", value: lastWornText)
        }
        .padding(.horizontal, 16)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이 옷의 다음 상태")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GarmentStatus.allCases) { status in
                        Button(status.rawValue) {
                            garment.status = status
                            try? modelContext.save()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(garment.status == status ? WEARyTheme.surface : WEARyTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            garment.status == status ? WEARyTheme.ink : WEARyTheme.surface,
                            in: Capsule()
                        )
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("이 옷을 입었던 날").font(.headline)
                Spacer()
                Text("총 \(garment.wearCount)회")
                    .font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
            }

            if wornOutfits.isEmpty {
                Label("아직 착용 기록이 없어요", systemImage: "calendar")
                    .font(.subheadline).foregroundStyle(WEARyTheme.secondaryInk)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(wornOutfits) { outfit in
                            GarmentWearHistoryCard(outfit: outfit, focusedGarment: garment)
                        }
                    }
                }
            }
        }
    }

    private var wornOutfits: [Outfit] {
        garment.confirmedOutfitItems
            .compactMap(\.outfit)
            .sorted { $0.wornAt > $1.wornAt }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("옷장에서 삭제", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var sellButton: some View {
        Button {
            showingListingEditor = true
        } label: {
            Label("이 옷 판매하기", systemImage: "tag")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.borderedProminent)
        .tint(WEARyTheme.ink)
    }

    private func informationRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(WEARyTheme.secondaryInk)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.vertical, 15)
    }

    private var priceText: String {
        guard let price = garment.purchasePrice else { return "미입력" }
        return price.formatted(.currency(code: "KRW").precision(.fractionLength(0)))
    }

    private var costPerWearText: String {
        guard let cost = garment.costPerWear else { return "—" }
        return cost.formatted(.number.notation(.compactName)) + "원"
    }

    private var purchaseDateText: String {
        garment.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "미입력"
    }

    private var lastWornText: String {
        garment.lastWornAt?.formatted(date: .abbreviated, time: .omitted) ?? "아직 없음"
    }
}

private struct GarmentWearHistoryCard: View {
    let outfit: Outfit
    let focusedGarment: Garment

    private var companionGarments: [Garment] {
        outfit.items.compactMap(\.garment).filter { $0.id != focusedGarment.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: focusedGarment.colorHex).opacity(0.72), WEARyTheme.canvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let data = outfit.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    HStack(spacing: -4) {
                        GarmentCutoutThumbnail(garment: focusedGarment).frame(width: 52, height: 74)
                        ForEach(companionGarments.prefix(2)) { garment in
                            GarmentCutoutThumbnail(garment: garment).frame(width: 42, height: 58)
                        }
                    }
                }
            }
            .frame(width: 150, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(outfit.wornAt.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.subheadline.weight(.bold))
            HStack {
                Text(outfit.wornAt.formatted(date: .omitted, time: .shortened))
                if outfit.isPublished { Image(systemName: "person.2.fill") }
            }
            .font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
        }
        .padding(10)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(outfit.wornAt.formatted(date: .long, time: .shortened)) 착장")
    }
}
