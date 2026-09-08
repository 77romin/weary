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
        Array(outfit.items.compactMap(\.garment).prefix(4))
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
    let date: Date
    let outfits: [Outfit]

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
        }
    }

    private func outfitCard(_ outfit: Outfit) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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
            }

            ForEach(outfit.items.compactMap(\.garment)) { garment in
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
        .padding(18)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))
    }
}
