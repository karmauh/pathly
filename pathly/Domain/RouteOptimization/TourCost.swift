import Foundation

/// Szybki, tylko do odczytu widok na macierz czasów przejazdu.
///
/// Algorytm trasy odczytuje koszty setki tysięcy razy, dlatego korzysta
/// bezpośrednio ze wskaźnika na ciągłą pamięć tablicy zamiast przez metody
/// `CostMatrix`. Istnieje tylko wewnątrz `CostMatrix.withDurationTable`.
nonisolated struct CostTable {
    let count: Int
    private let values: UnsafeBufferPointer<Double>

    init(count: Int, values: UnsafeBufferPointer<Double>) {
        precondition(values.count == count * count, "Nieprawidłowy rozmiar macierzy")
        self.count = count
        self.values = values
    }

    /// Koszt przejazdu z punktu `from` do `to` (macierz asymetryczna).
    @inline(__always)
    subscript(from: Int, to: Int) -> Double {
        values[from &* count &+ to]
    }
}

nonisolated extension CostMatrix {
    /// Udostępnia czasy przejazdu jako `CostTable` na czas wykonania `body`.
    func withDurationTable<Result>(_ body: (CostTable) throws -> Result) rethrows -> Result {
        try durations.withUnsafeBufferPointer { buffer in
            try body(CostTable(count: count, values: buffer))
        }
    }
}

/// Liczenie kosztu trasy zamkniętej w bazie.
///
/// Trasa jest zapisana jako tablica indeksów macierzy, która zaczyna się
/// i kończy bazą: `[0, s₁, s₂, …, sₙ, 0]`. Koszt to suma krawędzi
/// **skierowanych** — przy macierzy asymetrycznej trasa odwrócona ma inny koszt.
nonisolated enum TourCost {
    /// Indeks bazy w macierzy kosztów — punkt startu i końca każdej trasy.
    static let baseIndex = 0

    /// Trasa zamknięta w bazie dla podanej kolejności przystanków.
    static func closedTour(stops: [Int]) -> [Int] {
        [baseIndex] + stops + [baseIndex]
    }

    /// Przystanki trasy bez bazy na początku i końcu.
    static func stops(of tour: [Int]) -> [Int] {
        Array(tour.dropFirst().dropLast())
    }

    static func duration(of tour: [Int], in table: CostTable) -> Double {
        sum(of: tour) { table[$0, $1] }
    }

    /// Łączny czas przejazdu baza → przystanki → baza w sekundach.
    static func duration(stops: [Int], in matrix: CostMatrix) -> Double {
        sum(of: closedTour(stops: stops)) { matrix.duration(from: $0, to: $1) }
    }

    /// Łączny dystans baza → przystanki → baza w metrach.
    static func distance(stops: [Int], in matrix: CostMatrix) -> Double {
        sum(of: closedTour(stops: stops)) { matrix.distance(from: $0, to: $1) }
    }

    private static func sum(of tour: [Int], cost: (Int, Int) -> Double) -> Double {
        guard tour.count > 1 else { return 0 }
        var total = 0.0
        for position in 0..<(tour.count - 1) {
            total += cost(tour[position], tour[position + 1])
        }
        return total
    }
}
