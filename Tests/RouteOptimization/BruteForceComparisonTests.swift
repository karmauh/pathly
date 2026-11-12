import Foundation
import Testing
@testable import pathly

@Suite("Porównanie z rozwiązaniem optymalnym (brute force)")
struct BruteForceComparisonTests {
    let optimizer = RouteOptimizer()

    @Test("Do 4 przystanków — zawsze optimum", arguments: [1, 2, 3, 4])
    func optimalForTinyRoutes(stops: Int) throws {
        for seed in 0..<50 as Range<UInt64> {
            let matrix = RouteTestMatrices.random(count: stops + 1, seed: seed)
            let route = try optimizer.solve(matrix, deadline: .never)
            #expect(abs(route.totalDuration - RouteTestMatrices.bruteForceOptimum(matrix)) < 1e-6, "seed \(seed)")
        }
    }

    @Test("5–7 przystanków — najwyżej 5% powyżej optimum", arguments: [5, 6, 7])
    func nearOptimalForSmallRoutes(stops: Int) throws {
        var gaps: [Double] = []
        for seed in 0..<30 as Range<UInt64> {
            let matrix = RouteTestMatrices.random(count: stops + 1, seed: 1000 + seed)
            let optimum = RouteTestMatrices.bruteForceOptimum(matrix)
            let route = try optimizer.solve(matrix, deadline: .never)

            #expect(route.totalDuration >= optimum - 1e-6, "Heurystyka nie może być lepsza od optimum")
            let gap = route.totalDuration / optimum - 1
            #expect(gap <= 0.05, "seed \(seed): \(gap)")
            gaps.append(gap)
        }
        let optimal = gaps.filter { $0 < 1e-9 }.count
        let average = gaps.reduce(0, +) / Double(gaps.count) * 100
        let worst = (gaps.max() ?? 0) * 100
        Attachment.record("\(stops) przystanków: optimum w \(optimal)/\(gaps.count), średnio +\(average.formatted(.number.precision(.fractionLength(2)))) %, najgorzej +\(worst.formatted(.number.precision(.fractionLength(2)))) %", named: "statystyki.txt")
    }
}
