import Foundation

/// Pojedynczy kandydat zwrócony przez geokoder.
nonisolated struct GeocodingCandidate: Hashable, Sendable {
    var coordinate: Coordinate
    /// Adres w postaci zwróconej przez geokoder, do pokazania kurierowi.
    var label: String
    /// Miejscowość według geokodera (dla wsi bywa to nazwa gminy).
    var city: String?
    /// Kod pocztowy według geokodera.
    var postalCode: String?

    init(coordinate: Coordinate, label: String, city: String? = nil, postalCode: String? = nil) {
        self.coordinate = coordinate
        self.label = label
        self.city = city
        self.postalCode = postalCode
    }
}

/// Wynik geokodowania jednego adresu.
nonisolated enum GeocodingResult: Hashable, Sendable {
    case found(GeocodingCandidate)
    case notFound
    /// Kilka odległych od siebie miejsc pasuje do adresu.
    case ambiguous([GeocodingCandidate])
}

/// Błędy techniczne geokodowania (brak wyniku to nie błąd, tylko `.notFound`).
nonisolated enum GeocodingError: LocalizedError, Hashable, Sendable {
    /// Przekroczono limit zapytań Apple — warto ponowić później.
    case rateLimited
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            "Przekroczono limit zapytań geokodowania. Spróbuj ponownie za chwilę."
        case .failed(let reason):
            "Nie udało się ustalić położenia adresu: \(reason)"
        }
    }
}

/// Zamiana adresu na współrzędne. Implementacja produkcyjna: `MapKitGeocoder`.
protocol Geocoder {
    func geocode(_ address: Address) async throws -> GeocodingResult
}

/// Zamienia surową listę kandydatów z geokodera na `GeocodingResult`.
///
/// Dwa kroki:
/// 1. **Odrzucenie niepasujących kandydatów.** Geokoder Apple, gdy nie zna adresu,
///    potrafi zwrócić pojedynczy wynik z zupełnie innego miejsca (np. dla
///    „pl. Defilad 1, Warszawa” — „Warszówka 1, 62-800 Blizanów”). Kandydat musi
///    zgadzać się z zapytaniem co do miejscowości albo kodu pocztowego. Samego kodu
///    nie wymagamy, bo geokoder często zwraca inny kod dla tego samego budynku.
/// 2. **Wykrycie niejednoznaczności.** Kilka punktów dla jednego budynku (np. wejścia)
///    to nadal wynik jednoznaczny, o ile leżą blisko siebie.
nonisolated enum GeocodingResultClassifier {
    /// Maksymalna odległość od pierwszego kandydata (w metrach), przy której
    /// pozostałe wyniki traktujemy jako to samo miejsce.
    static let samePlaceRadius: Double = 300

    static func classify(_ candidates: [GeocodingCandidate], for address: Address) -> GeocodingResult {
        let matching = candidates.filter { matches($0, address) }
        guard let first = matching.first else { return .notFound }
        let isAmbiguous = matching.dropFirst().contains {
            $0.coordinate.distance(to: first.coordinate) > samePlaceRadius
        }
        return isAmbiguous ? .ambiguous(matching) : .found(first)
    }

    /// Czy kandydat leży w miejscowości lub kodzie pocztowym z zapytania.
    static func matches(_ candidate: GeocodingCandidate, _ address: Address) -> Bool {
        let requestedCity = comparable(address.city)
        if let city = candidate.city, !requestedCity.isEmpty, comparable(city) == requestedCity {
            return true
        }
        // Wieś bywa zwracana z nazwą gminy jako miejscowością — wtedy szukamy
        // nazwy miejscowości w pełnym adresie.
        if !requestedCity.isEmpty, comparable(candidate.label).contains(requestedCity) {
            return true
        }
        if let postalCode = candidate.postalCode, !address.postalCode.isEmpty {
            return postalCode == address.postalCode
        }
        return false
    }

    /// Tekst do porównań: bez wielkości liter i znaków diakrytycznych.
    private static func comparable(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pl_PL"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
