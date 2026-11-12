import Foundation

/// Przesyłka gotowa do trasy: ma ustalone położenie i czeka na doręczenie.
nonisolated struct RouteStop: Hashable, Sendable {
    let parcelID: UUID
    let coordinate: Coordinate
}

/// Przesyłki, z których można wyliczyć trasę, oraz te, które to blokują.
nonisolated struct RouteCandidates: Hashable, Sendable {
    var stops: [RouteStop]
    /// Przesyłki bez położenia z winy adresu albo błędu — kurier musi je poprawić.
    var needingAttention: Int = 0
    /// Przesyłki, które wciąż czekają w kolejce geokodowania.
    var awaitingGeocoding: Int = 0
}

/// Wyliczona trasa w kategoriach przesyłek (a nie indeksów macierzy).
nonisolated struct PlannedRoute: Hashable, Sendable {
    /// Przesyłki w kolejności doręczeń, bez bazy na początku i końcu.
    let stopOrder: [UUID]
    let totalDuration: TimeInterval
    let totalDistance: Double
    let costSource: CostSource
    let approximationReason: ApproximationReason?
    /// Optymalizację przerwał limit czasu — trasa jest poprawna, ale może nie być najlepsza.
    let stoppedByTimeLimit: Bool
}

/// Etap wyliczania trasy — do paska postępu.
nonisolated enum RoutePlanningPhase: Hashable, Sendable {
    case fetchingMatrix(completedRequests: Int, totalRequests: Int)
    case optimizing

    /// Kolejność etapów — pozwala zignorować spóźnione powiadomienia o postępie.
    var rank: Int {
        switch self {
        case .fetchingMatrix(let completed, _): completed
        case .optimizing: .max
        }
    }
}

/// Powód, dla którego trasy nie da się wyliczyć.
nonisolated enum RoutePlanningError: LocalizedError, Hashable, Sendable {
    case missingBase
    case noStops
    case parcelsNeedAttention(count: Int)
    case parcelsAwaitingGeocoding(count: Int)

    var errorDescription: String? {
        switch self {
        case .missingBase:
            "Ustaw bazę w ustawieniach — trasa zaczyna się i kończy w bazie."
        case .noStops:
            "Brak przesyłek do doręczenia. Dodaj przesyłki, aby wyliczyć trasę."
        case .parcelsNeedAttention(let count):
            count == 1
                ? "1 przesyłka wymaga poprawy adresu. Popraw ją na liście przesyłek."
                : "Przesyłki wymagające poprawy adresu: \(count). Popraw je na liście przesyłek."
        case .parcelsAwaitingGeocoding(let count):
            "Trwa ustalanie położenia przesyłek (\(count)). Spróbuj za chwilę."
        }
    }
}

/// Wyliczanie trasy: punkty → macierz czasów przejazdu → optymalizacja →
/// kolejność przesyłek.
///
/// Baza zawsze ma indeks 0 macierzy, przystanki — kolejne indeksy w kolejności
/// `candidates.stops`. Bez UI i SwiftData: dane wejściowe przychodzą z magazynów.
nonisolated struct RoutePlanner: Sendable {
    let costProvider: any TravelCostProvider
    var optimizer = RouteOptimizer()

    /// Sprawdza, czy trasę da się wyliczyć, zanim padnie pierwsze zapytanie.
    func validate(base: Coordinate?, candidates: RouteCandidates) throws(RoutePlanningError) {
        guard base != nil else { throw .missingBase }
        guard candidates.needingAttention == 0 else { throw .parcelsNeedAttention(count: candidates.needingAttention) }
        guard candidates.awaitingGeocoding == 0 else { throw .parcelsAwaitingGeocoding(count: candidates.awaitingGeocoding) }
        guard !candidates.stops.isEmpty else { throw .noStops }
    }

    /// - Parameter progress: wywoływane z wątku w tle przy każdej zmianie etapu.
    /// - Throws: `RoutePlanningError`, `CancellationError`. Błędy usługi tras
    ///   nie wychodzą na zewnątrz — dostawca kosztów przechodzi wtedy na przybliżenie.
    func plan(
        base: Coordinate?,
        candidates: RouteCandidates,
        progress: (@Sendable (RoutePlanningPhase) -> Void)? = nil
    ) async throws -> PlannedRoute {
        try validate(base: base, candidates: candidates)
        guard let base else { throw RoutePlanningError.missingBase }

        let stops = candidates.stops
        let points = [base] + stops.map(\.coordinate)
        progress?(.fetchingMatrix(completedRequests: 0, totalRequests: 0))
        let matrix = try await costProvider.costMatrix(for: points) { matrixProgress in
            progress?(.fetchingMatrix(
                completedRequests: matrixProgress.completedRequests,
                totalRequests: matrixProgress.totalRequests
            ))
        }
        try Task.checkCancellation()

        progress?(.optimizing)
        let route = try await optimizer.optimize(matrix)

        return PlannedRoute(
            // Indeks macierzy `i` (od 1) to przystanek `stops[i − 1]`.
            stopOrder: route.stopOrder.map { stops[$0 - 1].parcelID },
            totalDuration: route.totalDuration,
            totalDistance: route.totalDistance,
            costSource: route.costSource,
            approximationReason: route.approximationReason,
            stoppedByTimeLimit: route.stoppedByTimeLimit
        )
    }
}
