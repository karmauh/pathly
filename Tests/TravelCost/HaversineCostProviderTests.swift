import Foundation
import Testing
@testable import pathly

@Suite("HaversineCostProvider i CostMatrix")
struct HaversineCostProviderTests {
    let krakow = Coordinate(latitude: 50.0614, longitude: 19.9366)
    let warszawa = Coordinate(latitude: 52.2297, longitude: 21.0122)

    @Test("Odległość z objazdem i czas ze średniej prędkości")
    func estimates() async throws {
        let matrix = try await HaversineCostProvider().costMatrix(for: [krakow, warszawa])

        let straight = krakow.distance(to: warszawa)
        #expect(abs(straight - 252_000) < 2_000, "Kraków–Warszawa w linii prostej to ok. 252 km")
        #expect(matrix.distance(from: 0, to: 1) == straight * 1.3)
        #expect(abs(matrix.duration(from: 0, to: 1) - straight * 1.3 / (35 / 3.6)) < 1e-6)
        #expect(matrix.source == .approximate)
    }

    @Test("Macierz symetryczna z zerową przekątną")
    func symmetric() {
        let points = MatrixFixture.points(5)
        let matrix = HaversineCostProvider.matrix(for: points, reason: .offline)
        for from in 0..<5 {
            #expect(matrix.duration(from: from, to: from) == 0)
            for to in 0..<5 {
                #expect(matrix.duration(from: from, to: to) == matrix.duration(from: to, to: from))
            }
        }
        #expect(matrix.approximationReason == .offline)
    }

    @Test("CostMatrix przechowuje wartości wierszami")
    func rowMajor() {
        let matrix = CostMatrix(count: 2, durations: [0, 10, 20, 0], distances: [0, 1, 2, 0], source: .roadNetwork)
        #expect(matrix.duration(from: 0, to: 1) == 10)
        #expect(matrix.duration(from: 1, to: 0) == 20)
        #expect(matrix.distance(from: 1, to: 0) == 2)
        #expect(!matrix.isApproximate)
    }

    @Test("Puste i jednoelementowe macierze")
    func degenerate() {
        #expect(HaversineCostProvider.matrix(for: [], reason: nil).count == 0)
        #expect(HaversineCostProvider.matrix(for: [krakow], reason: nil).durations == [0])
    }
}
