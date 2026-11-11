import Foundation

/// Adres doręczenia odczytany z etykiety, do zatwierdzenia przez kuriera.
nonisolated struct ParsedAddress: Hashable, Sendable {
    /// Na co kurier powinien zwrócić uwagę na ekranie podglądu.
    enum Warning: Hashable, Sendable, CaseIterable {
        /// Kod pocztowy poprawiono z typowych błędów OCR (np. `O` → `0`).
        case postalCodeCorrected
        /// Nie znaleziono numeru budynku.
        case missingBuildingNumber
        /// Na etykiecie nie było kotwicy odbiorcy — adres wybrany heurystycznie.
        case recipientNotMarked
    }

    var address: Address
    /// Ocena pewności 0–1: kotwica odbiorcy, komplet pól, pewność OCR, poprawki.
    var confidence: Double
    var warnings: Set<Warning>
}

/// Wynik parsowania etykiety.
nonisolated enum AddressParsingResult: Hashable, Sendable {
    /// Jednoznacznie wskazany adres odbiorcy.
    case recipient(ParsedAddress)
    /// Kilka możliwych adresów bez kotwic — wybiera kurier.
    /// Kolejność: od najbardziej prawdopodobnego (większa czcionka wyżej).
    case candidates([ParsedAddress])
    /// Nie znaleziono żadnego adresu odbiorcy.
    case notFound
}
