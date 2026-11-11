import Foundation
import MapKit

/// Geokodowanie przez `MKGeocodingRequest` (MapKit, iOS 26+).
///
/// Wyszukiwanie zawężamy do obszaru Polski i polskiej lokalizacji, a samo
/// zapytanie zawiera kraj („…, Polska”), co eliminuje dopasowania za granicą.
final class MapKitGeocoder: Geocoder {
    /// Region obejmujący Polskę z niewielkim zapasem.
    private static let polandRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.0, longitude: 19.4),
        span: MKCoordinateSpan(latitudeDelta: 6.5, longitudeDelta: 10.5)
    )

    func geocode(_ address: Address) async throws -> GeocodingResult {
        guard let request = MKGeocodingRequest(addressString: address.geocodingQuery) else {
            return .notFound
        }
        request.region = Self.polandRegion
        request.preferredLocale = Locale(identifier: "pl_PL")

        let mapItems: [MKMapItem]
        do {
            mapItems = try await request.mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return .notFound
        } catch let error as MKError where error.code == .loadingThrottled {
            throw GeocodingError.rateLimited
        } catch {
            throw GeocodingError.failed(error.localizedDescription)
        }

        let candidates = mapItems.map { item in
            let fullAddress = item.address?.fullAddress ?? item.name ?? ""
            return GeocodingCandidate(
                coordinate: Coordinate(item.location.coordinate),
                label: fullAddress,
                city: item.addressRepresentations?.cityName,
                // MKAddress nie ma osobnego pola z kodem — wyciągamy go z pełnego adresu.
                postalCode: fullAddress.firstMatch(of: /\d{2}-\d{3}/).map { String($0.output) }
            )
        }
        return GeocodingResultClassifier.classify(candidates, for: address)
    }
}
