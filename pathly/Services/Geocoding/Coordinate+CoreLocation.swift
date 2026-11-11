import CoreLocation

/// Konwersje między domenowym `Coordinate` a typem CoreLocation.
/// Trzymane w warstwie serwisów, żeby domena nie importowała CoreLocation.
extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
