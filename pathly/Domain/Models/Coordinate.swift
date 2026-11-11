import Foundation

/// Punkt na Ziemi w stopniach (WGS84).
///
/// Własny typ zamiast `CLLocationCoordinate2D`, aby domena (parser, algorytm
/// trasy) nie zależała od CoreLocation/MapKit i była w pełni `Sendable`,
/// `Codable` i `Hashable`.
nonisolated struct Coordinate: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Czy współrzędne mieszczą się w poprawnych zakresach.
    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

// MARK: - Odległość

extension Coordinate {
    /// Średni promień Ziemi w metrach (IUGG).
    nonisolated static let earthRadius: Double = 6_371_008.8

    /// Odległość w linii prostej (po kole wielkim) w metrach, wzór haversine.
    ///
    /// Używana do wykrywania niejednoznacznych wyników geokodowania, a w etapie 5
    /// jako przybliżona macierz kosztów, gdy OpenRouteService jest niedostępny.
    nonisolated func distance(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return Self.earthRadius * c
    }
}
