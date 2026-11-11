import Foundation

/// Przybliżona macierz kosztów z odległości w linii prostej.
///
/// Używana, gdy OpenRouteService jest niedostępny. Odległość po kole wielkim
/// mnożymy przez współczynnik objazdu (drogi nie biegną prosto), a czas liczymy
/// ze średniej prędkości w mieście. Macierz jest symetryczna.
nonisolated struct HaversineCostProvider: TravelCostProvider {
    /// O ile droga jest dłuższa od linii prostej (typowo 1,2–1,4 w miastach).
    static let detourFactor = 1.3
    /// Średnia prędkość przejazdu w m/s (35 km/h).
    static let averageSpeed = 35.0 / 3.6

    /// Powód przybliżenia zapisywany w macierzy.
    var reason: ApproximationReason?

    init(reason: ApproximationReason? = nil) {
        self.reason = reason
    }

    func costMatrix(
        for points: [Coordinate],
        progress: (@Sendable (MatrixProgress) -> Void)?
    ) async throws -> CostMatrix {
        Self.matrix(for: points, reason: reason)
    }

    /// Szacowana długość drogi w metrach.
    static func estimatedDistance(from: Coordinate, to: Coordinate) -> Double {
        from.distance(to: to) * detourFactor
    }

    /// Szacowany czas przejazdu w sekundach dla drogi o danej długości.
    static func estimatedDuration(forDistance distance: Double) -> Double {
        distance / averageSpeed
    }

    static func matrix(for points: [Coordinate], reason: ApproximationReason?) -> CostMatrix {
        let count = points.count
        var durations = [Double](repeating: 0, count: count * count)
        var distances = [Double](repeating: 0, count: count * count)
        for from in 0..<count {
            for to in (from + 1)..<count {
                let distance = estimatedDistance(from: points[from], to: points[to])
                let duration = estimatedDuration(forDistance: distance)
                distances[from * count + to] = distance
                distances[to * count + from] = distance
                durations[from * count + to] = duration
                durations[to * count + from] = duration
            }
        }
        return CostMatrix(
            count: count,
            durations: durations,
            distances: distances,
            source: .approximate,
            approximationReason: reason
        )
    }
}
