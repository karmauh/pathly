import Foundation

/// Postęp pobierania macierzy, która wymaga kilku zapytań.
nonisolated struct MatrixProgress: Hashable, Sendable {
    var completedRequests: Int
    var totalRequests: Int
}

/// Źródło macierzy kosztów przejazdu między punktami.
///
/// Implementacje: `OpenRouteServiceCostProvider` (sieć dróg),
/// `HaversineCostProvider` (przybliżenie) i `FallbackCostProvider`, który
/// łączy je z pamięcią podręczną. Reszta aplikacji zna tylko ten protokół.
nonisolated protocol TravelCostProvider: Sendable {
    /// - Parameter progress: wywoływane po każdym zakończonym zapytaniu.
    func costMatrix(
        for points: [Coordinate],
        progress: (@Sendable (MatrixProgress) -> Void)?
    ) async throws -> CostMatrix
}

nonisolated extension TravelCostProvider {
    /// Wariant bez raportowania postępu.
    func costMatrix(for points: [Coordinate]) async throws -> CostMatrix {
        try await costMatrix(for: points, progress: nil)
    }
}

/// Błędy pobierania macierzy z usługi tras.
nonisolated enum TravelCostError: Error, Hashable, Sendable {
    /// Brak sieci albo usługa nie odpowiada.
    case offline
    /// Przekroczono limit zapytań na minutę (HTTP 429).
    case rateLimited
    /// Wyczerpano dzienny limit zapytań.
    case quotaExhausted
    /// Klucz API odrzucony (HTTP 401/403).
    case invalidAPIKey
    /// Inny błąd HTTP.
    case serviceError(statusCode: Int)
    /// Odpowiedź w nieoczekiwanym formacie.
    case invalidResponse
}

nonisolated extension ApproximationReason {
    /// Powód przybliżenia odpowiadający błędowi usługi tras.
    init(_ error: any Error) {
        switch error as? TravelCostError {
        case .offline: self = .offline
        case .rateLimited, .quotaExhausted: self = .quotaExhausted
        case .invalidAPIKey: self = .invalidAPIKey
        case .serviceError, .invalidResponse, nil: self = .serviceError
        }
    }
}
