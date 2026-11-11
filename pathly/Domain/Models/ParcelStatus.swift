import Foundation

/// Wynik geokodowania adresu przesyłki.
nonisolated enum GeocodingStatus: String, Codable, Sendable, CaseIterable {
    /// Czeka w kolejce geokodowania.
    case pending
    /// Znaleziono jednoznaczne współrzędne.
    case succeeded
    /// Geokoder nie znalazł adresu — kurier musi go poprawić.
    case notFound
    /// Kilka różnych miejsc pasuje do adresu — kurier musi doprecyzować.
    case ambiguous
    /// Błąd techniczny (sieć, limit zapytań) — można ponowić.
    case failed

    /// Kurier musi coś zrobić (poprawić adres, wybrać miejsce albo ponowić),
    /// zanim przesyłka trafi do trasy.
    var needsAttention: Bool {
        switch self {
        case .notFound, .ambiguous, .failed: true
        case .pending, .succeeded: false
        }
    }
}

/// Stan doręczenia przesyłki podczas realizacji trasy.
nonisolated enum DeliveryStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case delivered
    case notDelivered
}
