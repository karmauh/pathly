import Foundation

/// Macierz, którą aplikacja dostaje zawsze: pamięć podręczna → sieć dróg →
/// przybliżenie.
///
/// Wyliczenie trasy nie kończy się błędem z powodu usługi tras — w najgorszym
/// razie dostaje macierz przybliżoną z powodem do pokazania kurierowi.
/// Jedynie anulowanie zadania jest przekazywane dalej.
nonisolated struct FallbackCostProvider: TravelCostProvider {
    /// Usługa sieci dróg; `nil`, gdy nie skonfigurowano klucza API.
    let primary: (any TravelCostProvider)?
    let cache: CostMatrixCache?

    init(primary: (any TravelCostProvider)?, cache: CostMatrixCache?) {
        self.primary = primary
        self.cache = cache
    }

    /// Konfiguracja produkcyjna: OpenRouteService, jeśli jest klucz.
    static func live(configuration: AppConfiguration) -> FallbackCostProvider {
        let primary = configuration.openRouteServiceAPIKey.map { key in
            OpenRouteServiceCostProvider(client: OpenRouteServiceClient(apiKey: key), limiter: RequestRateLimiter())
        }
        return FallbackCostProvider(primary: primary, cache: CostMatrixCache())
    }

    func costMatrix(
        for points: [Coordinate],
        progress: (@Sendable (MatrixProgress) -> Void)?
    ) async throws -> CostMatrix {
        if let cached = await cache?.matrix(for: points) {
            return cached
        }
        guard let primary else {
            return HaversineCostProvider.matrix(for: points, reason: .missingAPIKey)
        }
        do {
            let matrix = try await primary.costMatrix(for: points, progress: progress)
            await cache?.store(matrix, for: points)
            return matrix
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return HaversineCostProvider.matrix(for: points, reason: ApproximationReason(error))
        }
    }
}
