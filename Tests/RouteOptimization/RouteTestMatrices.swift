import Foundation
import Synchronization
@testable import pathly

/// Macierze i narzędzia pomocnicze dla testów algorytmu trasy.
enum RouteTestMatrices {
    /// Losowa macierz asymetryczna: czasy 60–1800 s, zerowa przekątna.
    static func random(count: Int, seed: UInt64) -> CostMatrix {
        var generator = SplitMix64(seed: seed)
        var durations = [Double](repeating: 0, count: count * count)
        for from in 0..<count {
            for to in 0..<count where from != to {
                durations[from * count + to] = Double.random(in: 60...1800, using: &generator).rounded()
            }
        }
        return CostMatrix(count: count, durations: durations, distances: durations.map { $0 * 10 }, source: .roadNetwork)
    }

    /// Baza i `count − 1` przystanków rozrzuconych po Krakowie (ok. 12 × 9 km).
    /// Czasy z haversine z losowym, asymetrycznym narzutem do 30% — jak ulice
    /// jednokierunkowe i skręty w lewo w prawdziwej macierzy.
    static func krakow(count: Int, seed: UInt64) -> CostMatrix {
        var generator = SplitMix64(seed: seed)
        let points = (0..<count).map { _ in
            Coordinate(
                latitude: Double.random(in: 50.00...50.10, using: &generator),
                longitude: Double.random(in: 19.85...20.02, using: &generator)
            )
        }
        let symmetric = HaversineCostProvider.matrix(for: points, reason: nil)
        let durations = symmetric.durations.map { $0 * Double.random(in: 1.0...1.3, using: &generator) }
        return CostMatrix(count: count, durations: durations, distances: symmetric.distances, source: .roadNetwork)
    }

    /// Ręcznie zapisana macierz `count × count` (wiersze = skąd).
    static func matrix(_ rows: [[Double]], source: CostSource = .roadNetwork) -> CostMatrix {
        let flat = rows.flatMap { $0 }
        return CostMatrix(count: rows.count, durations: flat, distances: flat, source: source)
    }

    /// Koszt optymalnej trasy policzony przeglądem wszystkich permutacji.
    static func bruteForceOptimum(_ matrix: CostMatrix) -> Double {
        var stops = Array(1..<matrix.count)
        var best = Double.infinity
        permute(&stops, from: 0) { order in
            best = min(best, TourCost.duration(stops: order, in: matrix))
        }
        return best
    }

    private static func permute(_ values: inout [Int], from start: Int, visit: ([Int]) -> Void) {
        guard start < values.count else { return visit(values) }
        for index in start..<values.count {
            values.swapAt(start, index)
            permute(&values, from: start + 1, visit: visit)
            values.swapAt(start, index)
        }
    }

    /// Czy kolejność obejmuje każdy przystanek macierzy dokładnie raz (bez bazy).
    static func isPermutationOfStops(_ order: [Int], in matrix: CostMatrix) -> Bool {
        order.sorted() == Array(1..<max(matrix.count, 1))
    }
}

/// Termin, który mija po zadanej liczbie sprawdzeń — limit czasu bez czekania.
final class CountdownDeadline: Sendable {
    private let remainingChecks: Mutex<Int>

    init(checks: Int) {
        remainingChecks = Mutex(checks)
    }

    var deadline: RouteDeadline {
        RouteDeadline { [self] in
            remainingChecks.withLock { remaining in
                remaining -= 1
                return remaining < 0
            }
        }
    }
}
