import Foundation

/// Wynik optymalizacji trasy.
nonisolated struct OptimizedRoute: Hashable, Sendable {
    /// Indeksy przystanków w macierzy kosztów w kolejności doręczeń, bez bazy
    /// na początku i końcu.
    let stopOrder: [Int]
    /// Łączny czas przejazdu baza → przystanki → baza w sekundach.
    let totalDuration: TimeInterval
    /// Łączny dystans tej samej trasy w metrach.
    let totalDistance: Double
    /// Czy trasę policzono na rzeczywistych czasach przejazdu, czy na przybliżeniu.
    let costSource: CostSource
    let approximationReason: ApproximationReason?
    /// `true`, gdy obliczenia przerwał limit czasu — wynik jest poprawny, ale
    /// przeszukiwanie nie doszło do końca.
    let stoppedByTimeLimit: Bool
    let statistics: Statistics

    nonisolated struct Statistics: Hashable, Sendable {
        /// Czas trasy z samego najbliższego sąsiada — punkt odniesienia dla poprawy.
        let initialDuration: TimeInterval
        /// Ile startów z zaburzeniem trasy wykonano do końca.
        let completedRestarts: Int
        let elapsed: Duration
    }

    var isApproximate: Bool { costSource == .approximate }
}

/// Termin zakończenia obliczeń. Zegar jest wstrzykiwany, żeby limit czasu
/// dało się przetestować bez czekania.
nonisolated struct RouteDeadline: Sendable {
    private let check: @Sendable () -> Bool

    init(hasExpired check: @escaping @Sendable () -> Bool) {
        self.check = check
    }

    var hasExpired: Bool { check() }

    static func after(_ limit: Duration) -> RouteDeadline {
        let end = ContinuousClock.now.advanced(by: limit)
        return RouteDeadline { ContinuousClock.now >= end }
    }

    static let never = RouteDeadline { false }
}

/// Optymalizacja kolejności doręczeń — asymetryczny problem komiwojażera
/// ze startem i końcem w bazie (indeks 0 macierzy).
///
/// 1. Konstrukcja: najbliższy sąsiad startujący z bazy.
/// 2. Poprawa: na przemian Or-opt (ograniczony do list najbliższych sąsiadów)
///    i 2-opt, aż żaden ruch nie skraca trasy.
/// 3. Multi-start: najlepsza trasa jest zaburzana ruchem „double bridge”
///    i ponownie poprawiana; lepszy wynik zastępuje dotychczasowy.
///
/// Optymalizowany jest czas przejazdu (kurier chce najszybszej trasy);
/// dystans jest tylko raportowany. Czysty Swift, bez UI, MapKit i sieci.
nonisolated struct RouteOptimizer: Sendable {
    nonisolated struct Configuration: Hashable, Sendable {
        /// Po tym czasie zwracany jest najlepszy dotąd wynik.
        var timeLimit: Duration = .seconds(2)
        /// Liczba startów z zaburzeniem trasy po pierwszym przeszukiwaniu.
        var restarts: Int = 30
        /// Ziarno zaburzeń — ta sama macierz daje zawsze tę samą trasę.
        var seed: UInt64 = 0x5EED
    }

    /// Najmniejsza zmiana kosztu (w sekundach) uznawana za poprawę. Chroni przed
    /// zapętleniem na błędach zaokrągleń liczb zmiennoprzecinkowych.
    static let improvementThreshold = 1e-6

    var configuration = Configuration()

    /// Liczy trasę w tle — poza głównym wątkiem — z limitem czasu z konfiguracji.
    ///
    /// - Throws: `CancellationError`, gdy zadanie zostanie anulowane.
    @concurrent
    func optimize(_ matrix: CostMatrix) async throws -> OptimizedRoute {
        try solve(matrix, deadline: .after(configuration.timeLimit))
    }

    /// Synchroniczne jądro algorytmu. Sprawdza anulowanie bieżącego zadania
    /// i termin między ruchami.
    func solve(_ matrix: CostMatrix, deadline: RouteDeadline) throws -> OptimizedRoute {
        precondition(matrix.count >= 1, "Macierz musi zawierać co najmniej bazę")
        let started = ContinuousClock.now

        var timedOut = false
        let shouldStop: () throws -> Bool = {
            try Task.checkCancellation()
            if !timedOut, deadline.hasExpired { timedOut = true }
            return timedOut
        }

        let (tour, initialDuration, completedRestarts) = try matrix.withDurationTable { table in
            let neighbors = NeighborLists(table: table)
            var best = NearestNeighborConstruction.tour(in: table)
            let initialDuration = TourCost.duration(of: best, in: table)
            try Self.localSearch(&best, table: table, neighbors: neighbors, shouldStop: shouldStop)
            var bestDuration = TourCost.duration(of: best, in: table)

            var generator = SplitMix64(seed: configuration.seed)
            var completedRestarts = 0
            // Przy 1–2 przystankach przeszukiwanie lokalne sprawdza już wszystkie kolejności.
            let canPerturb = best.count - 2 >= 3
            while canPerturb, completedRestarts < configuration.restarts, !(try shouldStop()) {
                var candidate = Perturbation.doubleBridge(best, using: &generator)
                try Self.localSearch(&candidate, table: table, neighbors: neighbors, shouldStop: shouldStop)
                // Nawet przerwany kandydat jest poprawną trasą — warto go porównać.
                let candidateDuration = TourCost.duration(of: candidate, in: table)
                if candidateDuration < bestDuration - Self.improvementThreshold {
                    best = candidate
                    bestDuration = candidateDuration
                }
                if !timedOut { completedRestarts += 1 }
            }
            return (best, initialDuration, completedRestarts)
        }

        let stops = TourCost.stops(of: tour)
        return OptimizedRoute(
            stopOrder: stops,
            totalDuration: TourCost.duration(stops: stops, in: matrix),
            totalDistance: TourCost.distance(stops: stops, in: matrix),
            costSource: matrix.source,
            approximationReason: matrix.approximationReason,
            stoppedByTimeLimit: timedOut,
            statistics: .init(
                initialDuration: initialDuration,
                completedRestarts: completedRestarts,
                elapsed: ContinuousClock.now - started
            )
        )
    }

    /// Or-opt i 2-opt na przemian, aż żaden nie poprawi trasy albo minie czas.
    static func localSearch(
        _ tour: inout [Int],
        table: CostTable,
        neighbors: NeighborLists? = nil,
        shouldStop: () throws -> Bool
    ) rethrows {
        var improved = true
        while improved {
            if try shouldStop() { return }
            let movedSegments = try OrOptImprover.improve(&tour, table: table, neighbors: neighbors, shouldStop: shouldStop)
            let reversedSegments = try TwoOptImprover.improve(&tour, table: table, shouldStop: shouldStop)
            improved = movedSegments || reversedSegments
        }
    }
}
