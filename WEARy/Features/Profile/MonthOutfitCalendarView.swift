import SwiftData
import SwiftUI

struct MonthOutfitCalendarView: View {
    private struct SelectedDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    let outfits: [Outfit]
    @State private var displayedMonth = Date.now
    @State private var selectedDay: SelectedDay?

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = 1
        return calendar
    }()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 14) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(monthDays) { day in
                    dayCell(day)
                }
            }
        }
        .padding(14)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28).stroke(WEARyTheme.line)
        }
        .accessibilityIdentifier("profile.calendar")
        .sheet(item: $selectedDay) { selection in
            DayOutfitDetailView(
                date: selection.date,
                outfits: outfits(on: selection.date, from: outfits)
            )
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            VStack(spacing: 1) {
                Text(displayedMonth.formatted(.dateTime.year()))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WEARyTheme.secondaryInk)
                Text(displayedMonth.formatted(.dateTime.month(.wide)))
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            Spacer()
            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(weekdayColor(index))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let dayOutfits = outfits(on: day.date, from: outfits)
        let isToday = calendar.isDateInToday(day.date)

        return Button {
            selectedDay = SelectedDay(date: day.date)
        } label: {
            VStack(spacing: 2) {
                Text(day.number)
                    .font(.caption2.weight(isToday ? .black : .semibold))
                    .foregroundStyle(dayNumberColor(day))
                    .frame(width: 22, height: 18)
                    .background(isToday ? WEARyTheme.lime : .clear, in: Capsule())

                if let outfit = dayOutfits.last {
                    OutfitMiniature(outfit: outfit)
                    if dayOutfits.count > 1 {
                        Text("+\(dayOutfits.count - 1)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(WEARyTheme.coral)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(
                dayOutfits.isEmpty ? Color.clear : WEARyTheme.canvas.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .opacity(day.isInDisplayedMonth ? 1 : 0.32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isToday ? "calendar.today" : "calendar.day.\(day.number)")
        .accessibilityLabel(dayAccessibilityLabel(day, outfitCount: dayOutfits.count))
    }

    private var monthDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return [] }

        let monthStart = monthInterval.start
        let leadingDays = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let normalizedLeading = (leadingDays + 7) % 7
        let visibleCount = Int(ceil(Double(normalizedLeading + dayRange.count) / 7.0)) * 7

        return (0..<visibleCount).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - normalizedLeading, to: monthStart) else {
                return nil
            }
            return CalendarDay(
                date: date,
                number: String(calendar.component(.day, from: date)),
                isInDisplayedMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
            )
        }
    }

    private func outfits(on date: Date, from source: [Outfit]) -> [Outfit] {
        source
            .filter { calendar.isDate($0.wornAt, inSameDayAs: date) && $0.isConfirmed }
            .sorted { $0.wornAt < $1.wornAt }
    }

    private func moveMonth(by offset: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        withAnimation(.snappy) { displayedMonth = nextMonth }
    }

    private func weekdayColor(_ index: Int) -> Color {
        if index == 0 { return WEARyTheme.coral }
        if index == 6 { return Color.blue.opacity(0.75) }
        return WEARyTheme.secondaryInk
    }

    private func dayNumberColor(_ day: CalendarDay) -> Color {
        if calendar.component(.weekday, from: day.date) == 1 { return WEARyTheme.coral }
        if calendar.component(.weekday, from: day.date) == 7 { return .blue.opacity(0.75) }
        return WEARyTheme.ink
    }

    private func dayAccessibilityLabel(_ day: CalendarDay, outfitCount: Int) -> String {
        "\(day.date.formatted(date: .long, time: .omitted)), 착장 \(outfitCount)개"
    }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let number: String
    let isInDisplayedMonth: Bool
    var id: Date { date }
}

private struct OutfitMiniature: View {
    let outfit: Outfit

    private var garments: [Garment] {
        Array(outfit.orderedItems.compactMap(\.garment).prefix(4))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(garments.enumerated()), id: \.element.id) { index, garment in
                GarmentCutoutThumbnail(garment: garment)
                    .frame(width: 34, height: 25)
                    .offset(y: CGFloat(index) * 12)
                    .zIndex(Double(garments.count - index))
            }
        }
        .frame(width: 38, height: 52, alignment: .top)
    }
}

private struct DayOutfitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var posts: [CommunityPost]
    let date: Date
    let outfits: [Outfit]
    @State private var editingOutfit: Outfit?
    @State private var deletingOutfit: Outfit?
    @State private var operationError: String?
    @State private var photoFacingOutfitIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()
                if outfits.isEmpty {
                    ContentUnavailableView(
                        "착장 기록이 없어요",
                        systemImage: "calendar.badge.plus",
                        description: Text("이날의 옷을 기억하고 있다면 착장 기록에서 추가해 보세요.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(outfits) { outfit in
                                outfitCard(outfit)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle(date.formatted(.dateTime.month().day().weekday(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .navigationDestination(for: Garment.self) { garment in
                GarmentDetailView(garment: garment)
            }
            .sheet(item: $editingOutfit) { outfit in
                OutfitEditorView(outfit: outfit)
            }
            .confirmationDialog(
                "이 착장 기록을 삭제할까요?",
                isPresented: Binding(
                    get: { deletingOutfit != nil },
                    set: { if !$0 { deletingOutfit = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("착장 삭제", role: .destructive) { deleteSelectedOutfit() }
            } message: {
                Text(deleteMessage)
            }
            .alert("처리하지 못했어요", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("확인") { operationError = nil }
            } message: {
                Text(operationError ?? "")
            }
        }
    }

    private func outfitCard(_ outfit: Outfit) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        toggleCardFace(for: outfit)
                    }
                } label: {
                    Image(systemName: isPhotoFacing(outfit) ? "list.bullet" : "photo.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(WEARyTheme.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(outfit.photoData == nil)
                .opacity(outfit.photoData == nil ? 0.35 : 1)
                .accessibilityLabel(isPhotoFacing(outfit) ? "아이템 목록 보기" : "실제 착장 사진 보기")
                .accessibilityIdentifier("outfit.flip.\(outfit.id.uuidString)")

                VStack(alignment: .leading, spacing: 3) {
                    Text(outfit.wornAt.formatted(date: .omitted, time: .shortened))
                        .font(.headline)
                    Text("\(outfit.items.count)개의 옷")
                        .font(.caption)
                        .foregroundStyle(WEARyTheme.secondaryInk)
                }
                Spacer()
                if outfit.isPublished {
                    Label("공개", systemImage: "person.2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WEARyTheme.coral)
                }
                Menu {
                    Button {
                        editingOutfit = outfit
                    } label: {
                        Label("착장 수정", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deletingOutfit = outfit
                    } label: {
                        Label("착장 삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(WEARyTheme.ink)
                }
                .accessibilityLabel("착장 관리")
                .accessibilityIdentifier("outfit.manage")
            }

            ZStack {
                outfitItemList(outfit)
                    .opacity(isPhotoFacing(outfit) ? 0 : 1)
                    .accessibilityHidden(isPhotoFacing(outfit))
                    .rotation3DEffect(
                        .degrees(isPhotoFacing(outfit) ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0)
                    )

                outfitPhoto(outfit)
                    .opacity(isPhotoFacing(outfit) ? 1 : 0)
                    .accessibilityHidden(!isPhotoFacing(outfit))
                    .rotation3DEffect(
                        .degrees(isPhotoFacing(outfit) ? 0 : -180),
                        axis: (x: 0, y: 1, z: 0)
                    )
            }
        }
        .padding(18)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))
    }

    private func outfitItemList(_ outfit: Outfit) -> some View {
        VStack(spacing: 12) {
            ForEach(outfit.orderedItems) { item in
                if let garment = item.garment {
                    NavigationLink(value: garment) {
                        HStack(spacing: 12) {
                            GarmentCutoutThumbnail(garment: garment)
                                .frame(width: 54, height: 54)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(garment.name).font(.subheadline.weight(.semibold))
                                Text("\(garment.brand) · \(garment.category.rawValue) · \(garment.size)")
                                    .font(.caption)
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("outfit.itemFace")
    }

    @ViewBuilder
    private func outfitPhoto(_ outfit: Outfit) -> some View {
        if let data = outfit.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .clipped()
                .accessibilityLabel("실제 촬영한 착장 사진")
                .accessibilityIdentifier("outfit.photoFace")
        } else {
            ContentUnavailableView("촬영 사진이 없어요", systemImage: "photo")
                .frame(maxWidth: .infinity)
        }
    }

    private func isPhotoFacing(_ outfit: Outfit) -> Bool {
        photoFacingOutfitIDs.contains(outfit.id)
    }

    private func toggleCardFace(for outfit: Outfit) {
        if isPhotoFacing(outfit) {
            photoFacingOutfitIDs.remove(outfit.id)
        } else if outfit.photoData != nil {
            photoFacingOutfitIDs.insert(outfit.id)
        }
    }

    private var linkedPosts: [CommunityPost] {
        guard let outfitID = deletingOutfit?.id else { return [] }
        return posts.filter { $0.outfit?.id == outfitID }
    }

    private var deleteMessage: String {
        linkedPosts.isEmpty
            ? "포함된 옷의 착용 횟수와 캘린더 기록도 함께 갱신됩니다."
            : "포함된 옷의 착용 횟수와 연결된 내 피드 게시물도 함께 삭제됩니다."
    }

    private func deleteSelectedOutfit() {
        guard let outfit = deletingOutfit else { return }
        do {
            try OutfitRecordService.delete(outfit, linkedPosts: linkedPosts, in: modelContext)
            deletingOutfit = nil
            dismiss()
        } catch {
            operationError = "착장 기록을 삭제하지 못했어요. 다시 시도해 주세요."
        }
    }
}

private struct OutfitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Garment.createdAt) private var garments: [Garment]

    let outfit: Outfit
    @State private var wornAt: Date
    @State private var note: String
    @State private var orderedGarmentIDs: [UUID]
    @State private var itemEditMode: EditMode = .active
    @State private var saveError: String?

    init(outfit: Outfit) {
        self.outfit = outfit
        _wornAt = State(initialValue: outfit.wornAt)
        _note = State(initialValue: outfit.note)
        _orderedGarmentIDs = State(initialValue: outfit.orderedItems.compactMap(\.garment?.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("착장 정보") {
                    DatePicker("입은 날짜와 시간", selection: $wornAt)
                    TextField("그날의 메모", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("outfit.note")
                }

                Section {
                    ForEach(selectedGarments) { garment in
                        HStack(spacing: 12) {
                            GarmentCutoutThumbnail(garment: garment)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(garment.name).fontWeight(.semibold)
                                Text("\(garment.category.rawValue) · \(garment.brand)")
                                    .font(.caption)
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                            Spacer()
                            Button {
                                remove(garment)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(WEARyTheme.coral)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(garment.name) 착장에서 빼기")
                        }
                    }
                    .onMove(perform: moveSelectedGarments)
                } header: {
                    Text("입은 옷 · \(orderedGarmentIDs.count)개")
                } footer: {
                    Text("오른쪽 핸들을 드래그해 순서를 바꿀 수 있어요. 옷을 빼거나 추가하면 착용 통계도 다시 계산됩니다.")
                }
                .accessibilityIdentifier("outfit.itemOrder")

                if !availableGarments.isEmpty {
                    Section("옷장에서 추가") {
                        ForEach(availableGarments) { garment in
                            Button {
                                add(garment)
                            } label: {
                                HStack(spacing: 12) {
                                    GarmentCutoutThumbnail(garment: garment)
                                        .frame(width: 48, height: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(garment.name).fontWeight(.semibold)
                                        Text("\(garment.category.rawValue) · \(garment.brand)")
                                            .font(.caption)
                                            .foregroundStyle(WEARyTheme.secondaryInk)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(WEARyTheme.coral)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if outfit.isPublished {
                    Section {
                        Label("현재 로컬 피드에 공개된 착장이에요.", systemImage: "person.2.fill")
                            .foregroundStyle(WEARyTheme.coral)
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
            .navigationTitle("착장 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .fontWeight(.bold)
                        .disabled(orderedGarmentIDs.isEmpty)
                        .accessibilityIdentifier("outfit.save")
                }
            }
            .environment(\.editMode, $itemEditMode)
        }
    }

    private var selectedGarments: [Garment] {
        let garmentsByID = Dictionary(uniqueKeysWithValues: garments.map { ($0.id, $0) })
        return orderedGarmentIDs.compactMap { garmentsByID[$0] }
    }

    private var availableGarments: [Garment] {
        let selectedIDs = Set(orderedGarmentIDs)
        return garments.filter { !selectedIDs.contains($0.id) }
    }

    private func add(_ garment: Garment) {
        guard !orderedGarmentIDs.contains(garment.id) else { return }
        orderedGarmentIDs.append(garment.id)
    }

    private func remove(_ garment: Garment) {
        orderedGarmentIDs.removeAll { $0 == garment.id }
    }

    private func moveSelectedGarments(from source: IndexSet, to destination: Int) {
        orderedGarmentIDs.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        do {
            try OutfitRecordService.update(
                outfit,
                wornAt: wornAt,
                note: note,
                selectedGarments: selectedGarments,
                in: modelContext
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
