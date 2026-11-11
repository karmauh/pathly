import Foundation

/// Polski adres pocztowy rozbity na pola.
///
/// Wspólny typ dla bazy, przesyłek i wyniku parsera etykiet. Nie zawiera
/// współrzędnych — te są wynikiem geokodowania i żyją obok adresu.
nonisolated struct Address: Hashable, Codable, Sendable {
    /// Ulica wraz z ewentualnym prefiksem („ul. Długa”, „al. Jana Pawła II”).
    /// Może być pusta: w małych miejscowościach adres to nazwa miejscowości i numer.
    var street: String
    var buildingNumber: String
    var apartmentNumber: String?
    var postalCode: String
    var city: String

    init(
        street: String,
        buildingNumber: String,
        apartmentNumber: String? = nil,
        postalCode: String,
        city: String
    ) {
        self.street = street
        self.buildingNumber = buildingNumber
        self.apartmentNumber = apartmentNumber
        self.postalCode = postalCode
        self.city = city
    }
}

// MARK: - Formatowanie

extension Address {
    /// „Długa 12/4” albo „Wólka 7” dla adresu bez ulicy.
    nonisolated var streetLine: String {
        var number = buildingNumber
        if let apartmentNumber, !apartmentNumber.isEmpty {
            number += "/\(apartmentNumber)"
        }
        let base = street.isEmpty ? city : street
        return [base, number].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// „Długa 12/4, 00-001 Warszawa” — do wyświetlania w interfejsie.
    nonisolated var singleLine: String {
        let cityLine = [postalCode, city].filter { !$0.isEmpty }.joined(separator: " ")
        return [streetLine, cityLine].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Zapytanie dla geokodera.
    ///
    /// Numer lokalu jest pomijany: nie zmienia położenia budynku, a potrafi
    /// zdezorientować geokoder (np. „12/4” czytane jako zakres numerów).
    nonisolated var geocodingQuery: String {
        var withoutApartment = self
        withoutApartment.apartmentNumber = nil
        return withoutApartment.singleLine + ", Polska"
    }
}

// MARK: - Normalizacja i walidacja

extension Address {
    /// Kopia z przyciętymi i scalonymi białymi znakami; pusty numer lokalu → `nil`.
    nonisolated func normalized() -> Address {
        func clean(_ value: String) -> String {
            value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let apartment = apartmentNumber.map(clean)
        return Address(
            street: clean(street),
            buildingNumber: clean(buildingNumber),
            apartmentNumber: apartment?.isEmpty == false ? apartment : nil,
            postalCode: clean(postalCode),
            city: clean(city)
        )
    }

    nonisolated enum ValidationError: Error, Hashable, Sendable {
        case missingBuildingNumber
        case missingCity
        case invalidPostalCode

        /// Komunikat dla kuriera.
        var message: String {
            switch self {
            case .missingBuildingNumber: "Podaj numer budynku."
            case .missingCity: "Podaj miejscowość."
            case .invalidPostalCode: "Kod pocztowy musi mieć format 00-000."
            }
        }
    }

    /// Lista problemów z adresem; pusta oznacza adres gotowy do geokodowania.
    /// Ulica jest opcjonalna (adresy wiejskie), kod pocztowy — wymagany.
    nonisolated var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []
        if buildingNumber.isEmpty { errors.append(.missingBuildingNumber) }
        if city.isEmpty { errors.append(.missingCity) }
        if postalCode.wholeMatch(of: /\d{2}-\d{3}/) == nil { errors.append(.invalidPostalCode) }
        return errors
    }
}
