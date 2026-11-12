import Foundation

/// Ruch Or-opt: przeniesienie segmentu 1–3 kolejnych przystanków w inne miejsce
/// trasy, **bez odwracania** jego kierunku.
///
/// Ponieważ segment zachowuje kierunek, jego wewnętrzny koszt się nie zmienia —
/// zmiana kosztu trasy to różnica trzech usuniętych i trzech dodanych krawędzi,
/// liczona w O(1) także dla macierzy asymetrycznej.
nonisolated enum OrOptImprover {
    static let maxSegmentLength = 3

    /// Zmiana kosztu po przeniesieniu segmentu `tour[start..<start+length]`
    /// między pozycje `insertAfter` i `insertAfter + 1`. Wartość ujemna to poprawa.
    static func delta(
        _ tour: [Int],
        segmentStart start: Int,
        length: Int,
        insertAfter position: Int,
        table: CostTable
    ) -> Double {
        let first = tour[start]
        let last = tour[start + length - 1]
        return insertionCost(tour, first: first, last: last, after: position, table: table)
            - removalGain(tour, segmentStart: start, length: length, table: table)
    }

    /// Przenosi segment w nowe miejsce (pozycje według trasy sprzed ruchu).
    static func apply(_ tour: inout [Int], segmentStart start: Int, length: Int, insertAfter position: Int) {
        let segment = Array(tour[start..<(start + length)])
        tour.removeSubrange(start..<(start + length))
        let insertionIndex = position < start ? position + 1 : position + 1 - length
        tour.insert(contentsOf: segment, at: insertionIndex)
    }

    /// Jedno przejście po wszystkich segmentach. Każdy segment trafia w najlepsze
    /// miejsce, jeśli to skraca trasę. Zwraca `true`, gdy trasa się poprawiła.
    ///
    /// - Parameters:
    ///   - neighbors: gdy podane, segment `first…last` jest wstawiany tylko za
    ///     najbliższymi poprzednikami `first` albo przed najbliższymi następnikami
    ///     `last`; `nil` — sprawdzane są wszystkie miejsca.
    ///   - shouldStop: wywoływane regularnie; `true` przerywa przejście
    ///     (limit czasu), wyrzucony błąd — anulowanie.
    static func improve(
        _ tour: inout [Int],
        table: CostTable,
        neighbors: NeighborLists? = nil,
        shouldStop: () throws -> Bool
    ) rethrows -> Bool {
        let lastStop = tour.count - 2
        guard lastStop >= 2 else { return false }
        let base = TourCost.baseIndex
        var positions = neighbors == nil ? [] : Self.positions(of: tour, pointCount: table.count)
        var improved = false

        for length in 1...min(maxSegmentLength, lastStop - 1) {
            for start in 1...(lastStop - length + 1) {
                if try shouldStop() { return improved }

                let gain = removalGain(tour, segmentStart: start, length: length, table: table)
                guard gain > RouteOptimizer.improvementThreshold else { continue }
                let first = tour[start]
                let last = tour[start + length - 1]

                var bestDelta = -RouteOptimizer.improvementThreshold
                var bestPosition = -1
                func consider(_ position: Int) {
                    guard position < start - 1 || position >= start + length else { return }
                    let delta = insertionCost(tour, first: first, last: last, after: position, table: table) - gain
                    if delta < bestDelta {
                        bestDelta = delta
                        bestPosition = position
                    }
                }

                if let neighbors {
                    // Baza występuje dwa razy: jako poprzednik to pozycja 0,
                    // jako następnik — powrót za ostatnim przystankiem.
                    for left in neighbors.predecessors[first] {
                        consider(left == base ? 0 : positions[left])
                    }
                    for right in neighbors.successors[last] {
                        consider(right == base ? lastStop : positions[right] - 1)
                    }
                } else {
                    for position in 0...lastStop { consider(position) }
                }

                if bestPosition >= 0 {
                    apply(&tour, segmentStart: start, length: length, insertAfter: bestPosition)
                    if neighbors != nil { positions = Self.positions(of: tour, pointCount: table.count) }
                    improved = true
                }
            }
        }
        return improved
    }

    /// `positions[punkt]` — miejsce przystanku w trasie (dla bazy bez znaczenia).
    private static func positions(of tour: [Int], pointCount: Int) -> [Int] {
        var positions = [Int](repeating: 0, count: pointCount)
        for position in 1..<(tour.count - 1) {
            positions[tour[position]] = position
        }
        return positions
    }

    /// O ile skraca się trasa po wycięciu segmentu i połączeniu jego sąsiadów.
    @inline(__always)
    private static func removalGain(_ tour: [Int], segmentStart start: Int, length: Int, table: CostTable) -> Double {
        let previous = tour[start - 1]
        let next = tour[start + length]
        return table[previous, tour[start]] + table[tour[start + length - 1], next] - table[previous, next]
    }

    /// O ile wydłuża się trasa po wstawieniu segmentu `first…last` za pozycją `position`.
    @inline(__always)
    private static func insertionCost(_ tour: [Int], first: Int, last: Int, after position: Int, table: CostTable) -> Double {
        let left = tour[position]
        let right = tour[position + 1]
        return table[left, first] + table[last, right] - table[left, right]
    }
}
