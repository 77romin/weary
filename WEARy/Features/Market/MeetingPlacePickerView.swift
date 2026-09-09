import MapKit
import SwiftUI

struct MeetingPlaceSelection: Equatable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MarketListing {
    var meetingPlaceSelection: MeetingPlaceSelection? {
        guard let meetingLatitude, let meetingLongitude else { return nil }
        return MeetingPlaceSelection(
            name: displayedMeetingPlace,
            address: meetingAddress ?? "",
            latitude: meetingLatitude,
            longitude: meetingLongitude
        )
    }
}

struct MeetingPlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSelection: MeetingPlaceSelection?
    let onSelect: (MeetingPlaceSelection) -> Void

    @State private var query: String
    @State private var results: [MKMapItem] = []
    @State private var selection: MeetingPlaceSelection?
    @State private var cameraPosition: MapCameraPosition
    @State private var isSearching = false
    @State private var searchMessage: String?

    init(
        initialSelection: MeetingPlaceSelection?,
        onSelect: @escaping (MeetingPlaceSelection) -> Void
    ) {
        self.initialSelection = initialSelection
        self.onSelect = onSelect
        _query = State(initialValue: initialSelection?.name ?? "")
        _selection = State(initialValue: initialSelection)
        _cameraPosition = State(initialValue: .region(Self.region(around: initialSelection?.coordinate)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                meetingMap
                Divider()
                searchResults
            }
            .background(WEARyTheme.canvas)
            .navigationTitle("만날 장소")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("선택") {
                        guard let selection else { return }
                        onSelect(selection)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(selection == nil)
                    .accessibilityIdentifier("market.placeConfirm")
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("역, 건물 또는 주소 검색", text: $query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { Task { await searchPlaces() } }
                .accessibilityIdentifier("market.placeQuery")
            Button {
                Task { await searchPlaces() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(WEARyTheme.ink)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            .accessibilityLabel("장소 검색")
            .accessibilityIdentifier("market.placeSearch")
        }
        .padding(14)
        .background(WEARyTheme.surface)
    }

    private var meetingMap: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let selection {
                    Marker(selection.name, coordinate: selection.coordinate)
                        .tint(WEARyTheme.coral)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .all))
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                selection = MeetingPlaceSelection(
                    name: "지도에서 지정한 위치",
                    address: coordinateText(coordinate),
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
        .frame(height: 320)
        .accessibilityIdentifier("market.placeMap")
    }

    @ViewBuilder
    private var searchResults: some View {
        if isSearching {
            ProgressView("장소를 찾고 있어요")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView(
                searchMessage ?? "장소를 검색하거나 지도를 눌러 핀을 놓으세요",
                systemImage: "mappin.and.ellipse"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(Array(results.enumerated()), id: \.offset) { _, item in
                Button {
                    select(item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name ?? "이름 없는 장소")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WEARyTheme.ink)
                        Text(item.placemark.title ?? "주소 정보 없음")
                            .font(.caption)
                            .foregroundStyle(WEARyTheme.secondaryInk)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @MainActor
    private func searchPlaces() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedQuery
        if let selection {
            request.region = Self.region(around: selection.coordinate)
        }

        do {
            results = try await MKLocalSearch(request: request).start().mapItems
            if results.isEmpty { searchMessage = "검색 결과가 없어요" }
        } catch {
            results = []
            searchMessage = "장소를 검색하지 못했어요. 지도를 눌러 직접 지정해 주세요."
        }
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        selection = MeetingPlaceSelection(
            name: item.name ?? "선택한 장소",
            address: item.placemark.title ?? coordinateText(coordinate),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        cameraPosition = .region(Self.region(around: coordinate))
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "위도 %.5f, 경도 %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func region(around coordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    }
}

struct MeetingPlaceMapCard: View {
    let selection: MeetingPlaceSelection

    private var position: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: selection.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: position) {
                Marker(selection.name, coordinate: selection.coordinate)
                    .tint(WEARyTheme.coral)
            }
            .frame(height: 180)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Label(selection.name, systemImage: "mappin.circle.fill")
                    .font(.subheadline.weight(.semibold))
                if !selection.address.isEmpty && selection.address != selection.name {
                    Text(selection.address)
                        .font(.caption)
                        .foregroundStyle(WEARyTheme.secondaryInk)
                        .lineLimit(2)
                }
            }
            .padding(14)
        }
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("market.meetingMap")
    }
}
