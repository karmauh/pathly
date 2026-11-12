import Foundation

/// Ruch 2-opt: odwrócenie kolejności przystanków `tour[i...j]`.
///
/// W macierzy symetrycznej wystarczyłoby porównać dwie krawędzie na brzegach.
/// Przy macierzy asymetrycznej odwrócony segment jedzie każdą swoją krawędzią
/// w przeciwnym kierunku, więc trzeba przeliczyć **cały** jego koszt. Robimy to
/// dokładnie, ale w O(1) dzięki sumom prefiksowym kosztów „w przód”
/// (`t[k] → t[k+1]`) i „w tył” (`t[k+1] → t[k]`), przeliczanym w O(n) po
/// każdym zastosowanym ruchu.
nonisolated enum TwoOptImprover {
    /// Sumy prefiksowe: `forward[k]` to koszt przejazdu `t[0] → … → t[k]`,
    /// `backward[k]` — koszt tych samych krawędzi pokonanych w przeciwnym kierunku.
    struct PrefixSums {
        var forward: [Double]
        var backward: [Double]

        init(tour: [Int], table: CostTable) {
            forward = [Double](repeating: 0, count: tour.count)
            backward = forward
            rebuild(tour: tour, table: table)
        }

        mutating func rebuild(tour: [Int], table: CostTable) {
            for position in 0..<(tour.count - 1) {
                forward[position + 1] = forward[position] + table[tour[position], tour[position + 1]]
                backward[position + 1] = backward[position] + table[tour[position + 1], tour[position]]
            }
        }
    }

    /// Zmiana kosztu po odwróceniu `tour[i...j]` (`1 ≤ i < j ≤ tour.count − 2`).
    /// Wartość ujemna to poprawa.
    @inline(__always)
    static func delta(_ tour: [Int], from i: Int, to j: Int, sums: PrefixSums, table: CostTable) -> Double {
        let before = tour[i - 1]
        let after = tour[j + 1]
        let first = tour[i]
        let last = tour[j]
        let oldCost = table[before, first] + (sums.forward[j] - sums.forward[i]) + table[last, after]
        let newCost = table[before, last] + (sums.backward[j] - sums.backward[i]) + table[first, after]
        return newCost - oldCost
    }

    /// Jedno przejście: dla każdego początku `i` wybiera najlepszy koniec `j`
    /// i odwraca segment, jeśli to skraca trasę. Zwraca `true` po poprawie.
    ///
    /// - Parameter shouldStop: jak w `OrOptImprover.improve`.
    static func improve(
        _ tour: inout [Int],
        table: CostTable,
        shouldStop: () throws -> Bool
    ) rethrows -> Bool {
        let lastStop = tour.count - 2
        guard lastStop >= 2 else { return false }
        var sums = PrefixSums(tour: tour, table: table)
        var improved = false

        for i in 1..<lastStop {
            if try shouldStop() { return improved }

            var bestDelta = -RouteOptimizer.improvementThreshold
            var bestEnd = -1
            for j in (i + 1)...lastStop {
                let delta = delta(tour, from: i, to: j, sums: sums, table: table)
                if delta < bestDelta {
                    bestDelta = delta
                    bestEnd = j
                }
            }

            if bestEnd >= 0 {
                tour[i...bestEnd].reverse()
                sums.rebuild(tour: tour, table: table)
                improved = true
            }
        }
        return improved
    }
}
