import Foundation

/// Trasa początkowa metodą najbliższego sąsiada.
///
/// Z bazy jedziemy zawsze do najbliższego (najszybciej osiągalnego) jeszcze
/// nieodwiedzonego przystanku, a na końcu wracamy do bazy. Wynik bywa o kilkanaście
/// procent gorszy od optimum, ale powstaje w O(n²) i jest dobrym punktem
/// wyjścia dla przeszukiwania lokalnego.
nonisolated enum NearestNeighborConstruction {
    /// Trasa `[0, …, 0]` obejmująca wszystkie punkty macierzy poza bazą.
    static func tour(in table: CostTable) -> [Int] {
        let base = TourCost.baseIndex
        var tour = [base]
        tour.reserveCapacity(table.count + 1)
        var visited = [Bool](repeating: false, count: table.count)
        visited[base] = true

        var current = base
        for _ in 1..<max(table.count, 1) {
            var nearest = -1
            var nearestCost = Double.infinity
            for candidate in 0..<table.count where !visited[candidate] {
                let cost = table[current, candidate]
                // Przy równych kosztach wygrywa niższy indeks — wynik jest powtarzalny.
                if cost < nearestCost || nearest == -1 {
                    nearest = candidate
                    nearestCost = cost
                }
            }
            visited[nearest] = true
            tour.append(nearest)
            current = nearest
        }

        tour.append(base)
        return tour
    }
}
