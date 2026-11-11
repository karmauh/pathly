#if DEBUG
import Foundation

/// Geokoder do podglądów SwiftUI — zawsze zwraca centrum Warszawy, bez sieci.
final class PreviewGeocoder: Geocoder {
    func geocode(_ address: Address) async throws -> GeocodingResult {
        .found(GeocodingCandidate(
            coordinate: Coordinate(latitude: 52.2297, longitude: 21.0122),
            label: address.singleLine
        ))
    }
}
#endif
