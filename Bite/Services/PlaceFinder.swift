import CoreLocation
import MapKit

/// The places around you, to say where a meal is from. Location is asked for the first time it
/// helps, while using the app only, and it stays on the phone: Apple Maps' own search is the
/// only thing that sees it.
@MainActor
@Observable
final class PlaceFinder: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        /// Location was never asked: show why, and a button to allow it.
        case askPermission
        case denied
        case searching
        case found
        case failed
    }

    struct Nearby: Identifiable, Hashable {
        let place: MealPlace
        /// Meters from you, when we know where you are.
        let distance: Double?
        var id: String { place.key }
    }

    private(set) var state: State = .idle
    private(set) var nearby: [Nearby] = []
    /// Where you are, once known, to measure how far a place is.
    private(set) var here: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiting: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// The places within a few minutes' walk, nearest first, asking for location the first time.
    func findNearby() async {
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            here = CLLocation(latitude: Self.demoHere.latitude, longitude: Self.demoHere.longitude)
            nearby = Self.demoPlaces.map { Nearby(place: $0, distance: distance(to: $0)) }
            state = .found
            return
        }
        #endif
        switch manager.authorizationStatus {
        case .notDetermined: state = .askPermission
        case .denied, .restricted: state = .denied
        default: await search()
        }
    }

    /// Finds where you are without asking: only when location is already allowed, to say how
    /// far places are.
    func locateIfAllowed() async {
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            here = CLLocation(latitude: Self.demoHere.latitude, longitude: Self.demoHere.longitude)
            return
        }
        #endif
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            here = await currentLocation()
        default:
            break
        }
    }

    /// Shows the system's location question; the search starts once it is answered yes.
    func allow() {
        manager.requestWhenInUseAuthorization()
    }

    /// Places by name, around you when we know where you are.
    func search(_ text: String) async -> [Nearby] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            let matches = Self.demoPlaces
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
                .map { Nearby(place: $0, distance: distance(to: $0)) }
            if !matches.isEmpty { return matches }
            here = here ?? CLLocation(latitude: Self.demoHere.latitude, longitude: Self.demoHere.longitude)
        }
        #endif
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.foodCategories)
        if let here {
            request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 6000, longitudinalMeters: 6000)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(12).compactMap { nearby(from: $0) }
    }

    /// Meters from you to a place, when both are known.
    func distance(to place: MealPlace) -> Double? {
        guard let here else { return nil }
        return place.distance(fromLatitude: here.coordinate.latitude, longitude: here.coordinate.longitude)
    }

    // MARK: Location

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.state == .askPermission { await self.search() }
            case .denied, .restricted:
                self.state = .denied
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.resume(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(with: nil) }
    }

    private func resume(with location: CLLocation?) {
        waiting?.resume(returning: location)
        waiting = nil
    }

    private func currentLocation() async -> CLLocation? {
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -120 {
            return recent
        }
        return await withCheckedContinuation { continuation in
            waiting?.resume(returning: nil)
            waiting = continuation
            manager.requestLocation()
        }
    }

    private func search() async {
        state = .searching
        guard let location = await currentLocation() else {
            state = .failed
            return
        }
        here = location
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 250)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.foodCategories)
        do {
            let response = try await MKLocalSearch(request: request).start()
            let found = response.mapItems.compactMap { nearby(from: $0) }
            nearby = Array(found.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }.prefix(8))
            state = .found
        } catch {
            state = .failed
        }
    }

    // MARK: Map items

    static let foodCategories: [MKPointOfInterestCategory] = [.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .nightlife]

    private func nearby(from item: MKMapItem) -> Nearby? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let placemark = item.placemark
        let place = MealPlace(
            name: name,
            area: placemark.subLocality ?? placemark.thoroughfare ?? placemark.locality,
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            category: Self.category(item.pointOfInterestCategory)
        )
        return Nearby(place: place, distance: distance(to: place))
    }

    private static func category(_ category: MKPointOfInterestCategory?) -> MealPlace.Category? {
        guard let category else { return nil }
        if category == .restaurant { return .restaurant }
        if category == .cafe { return .cafe }
        if category == .bakery { return .bakery }
        if category == .foodMarket { return .market }
        if [MKPointOfInterestCategory.brewery, .winery, .nightlife].contains(category) { return .bar }
        return nil
    }

    #if DEBUG || BITE_DEMO
    /// The screenshots and Bite Demo stand by the Parc de Milan in Lausanne.
    static let demoHere = (latitude: 46.51475, longitude: 6.62230)

    static let demoPlaces: [MealPlace] = [
        MealPlace(name: "El Beirout", area: "Parc de Milan", latitude: 46.51492, longitude: 6.62268, category: .restaurant),
        MealPlace(name: "Café du Parc", area: "Avenue de Cour", latitude: 46.51402, longitude: 6.62351, category: .cafe),
        MealPlace(name: "Boulangerie du Midi", area: "Avenue de Montoie", latitude: 46.51598, longitude: 6.62012, category: .bakery),
        MealPlace(name: "Pizzeria Milano", area: "Montoie", latitude: 46.51681, longitude: 6.62455, category: .restaurant),
    ]
    #endif
}

extension Double {
    /// "40 m", "1.2 km", as the reader's country measures a walk.
    var distanceText: String {
        Measurement(value: self, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
