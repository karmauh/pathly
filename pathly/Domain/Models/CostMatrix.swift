import Foundation

/// Macierz kosztów przejazdu między punktami trasy (asymetryczna: A→B ≠ B→A).
///
/// Wartości leżą w płaskich tablicach wierszami (`from * count + to`), a nie
/// w `[[Double]]` — algorytm trasy odczytuje je setki tysięcy razy, a jedna
/// ciągła tablica jest wyraźnie szybsza od tablicy tablic.
nonisolated struct CostMatrix: Hashable, Codable, Sendable {
    /// Liczba punktów (macierz ma `count × count` komórek).
    let count: Int
    /// Czasy przejazdu w sekundach.
    let durations: [Double]
    /// Odległości w metrach.
    let distances: [Double]
    let source: CostSource
    /// Dlaczego użyto przybliżenia — `nil` dla danych z sieci dróg.
    let approximationReason: ApproximationReason?
    /// Ile par w macierzy z sieci dróg uzupełniono przybliżeniem, bo usługa nie
    /// znalazła drogi (np. punkt daleko od jezdni).
    let estimatedPairCount: Int

    init(
        count: Int,
        durations: [Double],
        distances: [Double],
        source: CostSource,
        approximationReason: ApproximationReason? = nil,
        estimatedPairCount: Int = 0
    ) {
        precondition(durations.count == count * count, "Nieprawidłowy rozmiar macierzy czasów")
        precondition(distances.count == count * count, "Nieprawidłowy rozmiar macierzy odległości")
        self.count = count
        self.durations = durations
        self.distances = distances
        self.source = source
        self.approximationReason = approximationReason
        self.estimatedPairCount = estimatedPairCount
    }

    /// Czas przejazdu z punktu `from` do `to` w sekundach.
    @inline(__always)
    func duration(from: Int, to: Int) -> Double {
        durations[from * count + to]
    }

    /// Odległość z punktu `from` do `to` w metrach.
    @inline(__always)
    func distance(from: Int, to: Int) -> Double {
        distances[from * count + to]
    }

    var isApproximate: Bool { source == .approximate }
}

/// Powód, dla którego trasa liczona jest z przybliżenia zamiast z sieci dróg.
nonisolated enum ApproximationReason: String, Hashable, Codable, Sendable {
    case missingAPIKey
    case offline
    case quotaExhausted
    case invalidAPIKey
    case serviceError

    /// Komunikat dla kuriera.
    var message: String {
        switch self {
        case .missingAPIKey:
            "Brak klucza OpenRouteService — czasy przejazdu są szacowane z odległości."
        case .offline:
            "Brak połączenia z usługą tras — czasy przejazdu są szacowane z odległości."
        case .quotaExhausted:
            "Wyczerpano limit zapytań do usługi tras — czasy przejazdu są szacowane z odległości."
        case .invalidAPIKey:
            "Klucz OpenRouteService został odrzucony — czasy przejazdu są szacowane z odległości."
        case .serviceError:
            "Usługa tras zwróciła błąd — czasy przejazdu są szacowane z odległości."
        }
    }
}
