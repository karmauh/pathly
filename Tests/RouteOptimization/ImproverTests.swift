import Foundation
import Testing
@testable import pathly

@Suite("Or-opt i 2-opt")
struct ImproverTests {
    let matrix = RouteTestMatrices.random(count: 12, seed: 3)

    /// Losowa trasa zamknięta w bazie dla `matrix`.
    private func randomTour(_ generator: inout SplitMix64) -> [Int] {
        TourCost.closedTour(stops: Array(1..<matrix.count).shuffled(using: &generator))
    }

    @Test("Or-opt: zmiana kosztu O(1) równa pełnemu przeliczeniu trasy")
    func orOptDeltaMatchesFullCost() {
        var generator = SplitMix64(seed: 11)
        matrix.withDurationTable { table in
            for _ in 0..<300 {
                let tour = randomTour(&generator)
                let lastStop = tour.count - 2
                let length = Int.random(in: 1...3, using: &generator)
                let start = Int.random(in: 1...(lastStop - length + 1), using: &generator)
                let allowed = (0...lastStop).filter { $0 < start - 1 || $0 >= start + length }
                let position = allowed.randomElement(using: &generator)!

                var moved = tour
                OrOptImprover.apply(&moved, segmentStart: start, length: length, insertAfter: position)
                let expected = TourCost.duration(of: moved, in: table) - TourCost.duration(of: tour, in: table)
                let delta = OrOptImprover.delta(tour, segmentStart: start, length: length, insertAfter: position, table: table)

                #expect(abs(delta - expected) < 1e-6)
                #expect(moved.sorted() == tour.sorted(), "Ruch nie gubi ani nie dubluje przystanków")
                #expect(moved.first == 0 && moved.last == 0)
            }
        }
    }

    @Test("Or-opt przenosi segment bez odwracania")
    func orOptKeepsDirection() {
        var tour = [0, 1, 2, 3, 4, 5, 0]
        OrOptImprover.apply(&tour, segmentStart: 1, length: 2, insertAfter: 4)
        #expect(tour == [0, 3, 4, 1, 2, 5, 0])
        OrOptImprover.apply(&tour, segmentStart: 3, length: 2, insertAfter: 0)
        #expect(tour == [0, 1, 2, 3, 4, 5, 0])
    }

    @Test("2-opt: koszt odwróconego segmentu z sum prefiksowych równy pełnemu przeliczeniu")
    func twoOptDeltaMatchesFullCost() {
        var generator = SplitMix64(seed: 12)
        matrix.withDurationTable { table in
            for _ in 0..<300 {
                let tour = randomTour(&generator)
                let lastStop = tour.count - 2
                let i = Int.random(in: 1..<lastStop, using: &generator)
                let j = Int.random(in: (i + 1)...lastStop, using: &generator)

                var reversed = tour
                reversed[i...j].reverse()
                let expected = TourCost.duration(of: reversed, in: table) - TourCost.duration(of: tour, in: table)
                let sums = TwoOptImprover.PrefixSums(tour: tour, table: table)
                let delta = TwoOptImprover.delta(tour, from: i, to: j, sums: sums, table: table)

                #expect(abs(delta - expected) < 1e-6)
            }
        }
    }

    @Test("2-opt nie myli się na macierzy asymetrycznej — sam brzeg segmentu nie wystarcza")
    func twoOptUsesWholeSegmentCost() {
        // Krawędzie brzegowe po odwróceniu są tańsze, ale segment 1→2→3 jedzie
        // tanio tylko w przód: odwrócenie musi wyjść niekorzystne.
        let matrix = RouteTestMatrices.matrix([
            [0, 5, 9, 1, 9],
            [9, 0, 1, 9, 9],
            [9, 100, 0, 1, 9],
            [9, 9, 100, 0, 5],
            [5, 9, 9, 9, 0],
        ])
        matrix.withDurationTable { table in
            let tour = [0, 1, 2, 3, 4, 0]
            let sums = TwoOptImprover.PrefixSums(tour: tour, table: table)
            // Brzegi: (0→1)+(3→4) = 10 przed, (0→3)+(1→4) = 10 po — symetryczna
            // wersja 2-opt widziałaby zmianę 0, a naprawdę jest +198.
            #expect(TwoOptImprover.delta(tour, from: 1, to: 3, sums: sums, table: table) == 198)

            var improved = tour
            _ = TwoOptImprover.improve(&improved, table: table) { false }
            #expect(TourCost.duration(of: improved, in: table) <= TourCost.duration(of: tour, in: table))
        }
    }

    @Test("Żaden ruch nie pogarsza trasy, a przeszukiwanie lokalne kończy w minimum",
          arguments: [1, 2, 3, 4, 5] as [UInt64])
    func neverWorsens(seed: UInt64) {
        var generator = SplitMix64(seed: seed)
        let matrix = RouteTestMatrices.random(count: 30, seed: seed)
        matrix.withDurationTable { table in
            var tour = TourCost.closedTour(stops: Array(1..<30).shuffled(using: &generator))
            var cost = TourCost.duration(of: tour, in: table)

            for _ in 0..<50 {
                _ = OrOptImprover.improve(&tour, table: table) { false }
                let afterOrOpt = TourCost.duration(of: tour, in: table)
                #expect(afterOrOpt <= cost + 1e-9)
                _ = TwoOptImprover.improve(&tour, table: table) { false }
                let afterTwoOpt = TourCost.duration(of: tour, in: table)
                #expect(afterTwoOpt <= afterOrOpt + 1e-9)
                cost = afterTwoOpt
            }

            RouteOptimizer.localSearch(&tour, table: table) { false }
            #expect(!OrOptImprover.improve(&tour, table: table) { false })
            #expect(!TwoOptImprover.improve(&tour, table: table) { false })
            #expect(RouteTestMatrices.isPermutationOfStops(TourCost.stops(of: tour), in: matrix))
        }
    }

    @Test("Listy sąsiadów: K najbliższych w kierunku jazdy, a Or-opt z nimi nie pogarsza trasy")
    func neighborLists() {
        let matrix = RouteTestMatrices.krakow(count: 60, seed: 21)
        matrix.withDurationTable { table in
            let neighbors = NeighborLists(table: table, size: 5)
            for node in 0..<60 {
                #expect(neighbors.successors[node].count == 5)
                #expect(!neighbors.successors[node].contains(node))
                let farthestListed = neighbors.successors[node].map { table[node, $0] }.max()!
                let closestOther = (0..<60).filter { $0 != node && !neighbors.successors[node].contains($0) }
                    .map { table[node, $0] }.min()!
                #expect(farthestListed <= closestOther)
                let farthestPredecessor = neighbors.predecessors[node].map { table[$0, node] }.max()!
                let closestOtherPredecessor = (0..<60).filter { $0 != node && !neighbors.predecessors[node].contains($0) }
                    .map { table[$0, node] }.min()!
                #expect(farthestPredecessor <= closestOtherPredecessor)
            }

            var generator = SplitMix64(seed: 22)
            var tour = TourCost.closedTour(stops: Array(1..<60).shuffled(using: &generator))
            var cost = TourCost.duration(of: tour, in: table)
            for _ in 0..<20 {
                _ = OrOptImprover.improve(&tour, table: table, neighbors: neighbors) { false }
                let next = TourCost.duration(of: tour, in: table)
                #expect(next <= cost + 1e-9)
                cost = next
            }
            #expect(RouteTestMatrices.isPermutationOfStops(TourCost.stops(of: tour), in: matrix))
        }
    }

    @Test("Trasa z 0–2 przystankami nie zmienia się przy braku poprawy")
    func smallTours() {
        let matrix = RouteTestMatrices.matrix([[0, 1, 1], [1, 0, 1], [1, 1, 0]])
        matrix.withDurationTable { table in
            var empty = [0, 0]
            #expect(!OrOptImprover.improve(&empty, table: table) { false })
            #expect(!TwoOptImprover.improve(&empty, table: table) { false })
            var single = [0, 1, 0]
            #expect(!OrOptImprover.improve(&single, table: table) { false })
            #expect(!TwoOptImprover.improve(&single, table: table) { false })
            var pair = [0, 1, 2, 0]
            #expect(!TwoOptImprover.improve(&pair, table: table) { false })
            #expect(pair == [0, 1, 2, 0])
        }
    }
}
