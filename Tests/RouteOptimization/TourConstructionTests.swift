import Foundation
import Testing
@testable import pathly

@Suite("Koszt trasy i najbliższy sąsiad")
struct TourConstructionTests {
    /// Asymetria: 0→1→2→0 kosztuje 1 + 1 + 1, a 0→2→1→0 kosztuje 10 + 10 + 10.
    let asymmetric = RouteTestMatrices.matrix([
        [0, 1, 10],
        [10, 0, 1],
        [1, 10, 0],
    ])

    @Test("Koszt liczony po krawędziach skierowanych — trasa odwrócona kosztuje inaczej")
    func asymmetricCost() {
        #expect(TourCost.duration(stops: [1, 2], in: asymmetric) == 3)
        #expect(TourCost.duration(stops: [2, 1], in: asymmetric) == 30)
        #expect(TourCost.distance(stops: [1, 2], in: asymmetric) == 3)
        asymmetric.withDurationTable { table in
            #expect(TourCost.duration(of: [0, 2, 1, 0], in: table) == 30)
        }
    }

    @Test("Trasa bez przystanków i z jednym przystankiem")
    func degenerateCost() {
        let matrix = RouteTestMatrices.matrix([[0, 7], [5, 0]])
        #expect(TourCost.duration(stops: [], in: matrix) == 0)
        #expect(TourCost.duration(stops: [1], in: matrix) == 12)
        #expect(TourCost.closedTour(stops: [3, 1]) == [0, 3, 1, 0])
        #expect(TourCost.stops(of: [0, 3, 1, 0]) == [3, 1])
    }

    @Test("Najbliższy sąsiad wybiera najszybszy przejazd w kierunku jazdy")
    func nearestNeighbor() {
        asymmetric.withDurationTable { table in
            #expect(NearestNeighborConstruction.tour(in: table) == [0, 1, 2, 0])
        }
        let matrix = RouteTestMatrices.matrix([
            [0, 5, 2, 9],
            [5, 0, 1, 1],
            [2, 8, 0, 3],
            [9, 1, 3, 0],
        ])
        matrix.withDurationTable { table in
            // 0 → 2 (2), 2 → 3 (3), 3 → 1 (1), 1 → 0.
            #expect(NearestNeighborConstruction.tour(in: table) == [0, 2, 3, 1, 0])
        }
    }

    @Test("Najbliższy sąsiad bez przystanków i dla dużej macierzy")
    func nearestNeighborCoversAllStops() {
        RouteTestMatrices.matrix([[0]]).withDurationTable { table in
            #expect(NearestNeighborConstruction.tour(in: table) == [0, 0])
        }
        let matrix = RouteTestMatrices.random(count: 40, seed: 1)
        matrix.withDurationTable { table in
            let tour = NearestNeighborConstruction.tour(in: table)
            #expect(tour.first == 0 && tour.last == 0)
            #expect(RouteTestMatrices.isPermutationOfStops(TourCost.stops(of: tour), in: matrix))
        }
    }

    @Test("Double bridge zachowuje komplet przystanków i bazę na końcach")
    func doubleBridge() {
        var generator = SplitMix64(seed: 7)
        let tour = TourCost.closedTour(stops: Array(1...12))
        for _ in 0..<100 {
            let perturbed = Perturbation.doubleBridge(tour, using: &generator)
            #expect(perturbed.first == 0 && perturbed.last == 0)
            #expect(TourCost.stops(of: perturbed).sorted() == Array(1...12))
            #expect(perturbed != tour)
        }
    }

    @Test("SplitMix64 jest powtarzalny dla tego samego ziarna")
    func deterministicGenerator() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        #expect((0..<5).map { _ in first.next() } == (0..<5).map { _ in second.next() })
    }
}
