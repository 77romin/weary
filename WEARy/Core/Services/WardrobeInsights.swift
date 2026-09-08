import Foundation

enum InsightPeriod: Int, CaseIterable, Identifiable {
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtyDays: "30일"
        case .ninetyDays: "90일"
        case .oneYear: "1년"
        }
    }
}

struct GarmentUsage: Identifiable {
    let garment: Garment
    let count: Int
    var id: UUID { garment.id }
}

enum WardrobeInsights {
    static func wearCount(for garment: Garment, since startDate: Date) -> Int {
        garment.confirmedOutfitItems.filter { item in
            guard let wornAt = item.outfit?.wornAt else { return false }
            return wornAt >= startDate
        }.count
    }

    static func usage(
        garments: [Garment],
        period: InsightPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [GarmentUsage] {
        guard let startDate = calendar.date(byAdding: .day, value: -period.rawValue, to: now) else { return [] }
        return garments
            .map { GarmentUsage(garment: $0, count: wearCount(for: $0, since: startDate)) }
            .sorted {
                if $0.count == $1.count { return $0.garment.name < $1.garment.name }
                return $0.count > $1.count
            }
    }

    static func reviewCandidates(
        garments: [Garment],
        thresholdDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Garment] {
        guard let cutoff = calendar.date(byAdding: .day, value: -thresholdDays, to: now) else { return [] }
        return garments.filter { garment in
            guard garment.status == .active else { return false }
            let referenceDate = garment.lastWornAt ?? garment.purchaseDate ?? garment.createdAt
            return referenceDate < cutoff
        }
        .sorted {
            let lhs = $0.lastWornAt ?? $0.purchaseDate ?? $0.createdAt
            let rhs = $1.lastWornAt ?? $1.purchaseDate ?? $1.createdAt
            return lhs < rhs
        }
    }

    static func daysSinceLastUse(
        for garment: Garment,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let referenceDate = garment.lastWornAt ?? garment.purchaseDate ?? garment.createdAt
        return max(0, calendar.dateComponents([.day], from: referenceDate, to: now).day ?? 0)
    }
}
