import SwiftData
import SwiftUI

struct WardrobeView: View {
    @Query(sort: \Garment.createdAt, order: .reverse) private var garments: [Garment]
    @State private var searchText = ""
    @State private var selectedCategory: GarmentCategory?
    @State private var showingAddGarment = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var filteredGarments: [Garment] {
        garments.filter { garment in
            let matchesCategory = selectedCategory == nil || garment.category == selectedCategory
            let matchesSearch = searchText.isEmpty
                || garment.name.localizedStandardContains(searchText)
                || garment.brand.localizedStandardContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        wardrobeHeader
                        categoryPicker

                        if filteredGarments.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(filteredGarments) { garment in
                                    NavigationLink(value: garment) {
                                        GarmentCard(garment: garment)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("옷장")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "옷 이름 또는 브랜드")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddGarment = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("새 옷 등록")
                }
            }
            .navigationDestination(for: Garment.self) { garment in
                GarmentDetailView(garment: garment)
            }
            .sheet(isPresented: $showingAddGarment) {
                GarmentEditorView()
            }
        }
    }

    private var wardrobeHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MY CLOSET")
                    .font(.caption.weight(.black))
                    .tracking(1.8)
                    .foregroundStyle(WEARyTheme.coral)
                Text("가지고 있는 옷 \(garments.count)벌")
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            Spacer()
            Text("오늘도 내 옷답게")
                .font(.caption)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .padding(.top, 8)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(title: "전체", category: nil)
                ForEach(GarmentCategory.allCases) { category in
                    categoryButton(title: category.rawValue, category: category)
                }
            }
        }
        .contentMargins(.horizontal, 0)
    }

    private func categoryButton(title: String, category: GarmentCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button(title) {
            withAnimation(.snappy) { selectedCategory = category }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isSelected ? WEARyTheme.surface : WEARyTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isSelected ? WEARyTheme.ink : WEARyTheme.surface, in: Capsule())
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "아직 맞는 옷이 없어요",
            systemImage: "hanger",
            description: Text("필터를 바꾸거나 첫 번째 옷을 등록해 보세요.")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

private struct GarmentCard: View {
    let garment: Garment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GarmentArtwork(garment: garment, height: 176)
                .overlay(alignment: .topTrailing) {
                    Text(garment.status.rawValue)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(garment.brand.isEmpty ? garment.category.rawValue : garment.brand.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WEARyTheme.secondaryInk)
                    .lineLimit(1)
                Text(garment.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WEARyTheme.ink)
                    .lineLimit(1)
                Text("\(garment.wearCount)번 입음")
                    .font(.caption)
                    .foregroundStyle(WEARyTheme.coral)
            }
            .padding(12)
        }
        .background(WEARyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius)
                .stroke(WEARyTheme.line)
        }
    }
}
