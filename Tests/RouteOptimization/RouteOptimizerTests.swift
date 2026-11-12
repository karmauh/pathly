import Foundation
import Testing
@testable import pathly

@Suite("RouteOptimizer")
struct RouteOptimizerTests {
    let optimizer = RouteOptimizer()

    @Test("Każdy przystanek dokładnie raz, start i koniec w bazie, koszt zgodny z kolejnością",
          arguments: [2, 3, 10, 41, 80])
    func validPermutation(count: Int) throws {
        let matrix = RouteTestMatrices.random(count: count, seed: UInt64(count))
        let route = try optimizer.solve(matrix, deadline: .never)

        #expect(RouteTestMatrices.isPermutationOfStops(route.stopOrder, in: matrix))
        #expect(!route.stopOrder.contains(TourCost.baseIndex), "Baza jest tylko na początku i końcu")
        #expect(route.totalDuration == TourCost.duration(stops: route.stopOrder, in: matrix))
        #expect(route.totalDistance == TourCost.distance(stops: route.stopOrder, in: matrix))
        #expect(!route.stoppedByTimeLimit)
    }

    @Test("Wynik nie gorszy od najbliższego sąsiada", arguments: [10, 20, 30, 40, 50] as [UInt64])
    func notWorseThanConstruction(seed: UInt64) throws {
        let matrix = RouteTestMatrices.krakow(count: 60, seed: seed)
        let route = try optimizer.solve(matrix, deadline: .never)

        #expect(route.totalDuration <= route.statistics.initialDuration)
        let improvement = 1 - route.totalDuration / route.statistics.initialDuration
        Attachment.record("Poprawa względem najbliższego sąsiada (seed \(seed)): \((improvement * 100).formatted(.number.precision(.fractionLength(1)))) %", named: "statystyki.txt")
    }

    @Test("Multi-start nie pogarsza wyniku pojedynczego przeszukiwania")
    func restartsHelp() throws {
        let matrix = RouteTestMatrices.krakow(count: 80, seed: 99)
        var single = RouteOptimizer()
        single.configuration.restarts = 0

        let withoutRestarts = try single.solve(matrix, deadline: .never)
        let withRestarts = try optimizer.solve(matrix, deadline: .never)

        #expect(withoutRestarts.statistics.completedRestarts == 0)
        #expect(withRestarts.statistics.completedRestarts == optimizer.configuration.restarts)
        #expect(withRestarts.totalDuration <= withoutRestarts.totalDuration)
    }

    @Test("Ta sama macierz i ziarno — ta sama trasa")
    func deterministic() throws {
        let matrix = RouteTestMatrices.krakow(count: 50, seed: 5)
        #expect(try optimizer.solve(matrix, deadline: .never) .stopOrder
                == optimizer.solve(matrix, deadline: .never).stopOrder)
    }

    @Test("Bez przystanków i z jednym przystankiem")
    func degenerate() throws {
        let onlyBase = try optimizer.solve(RouteTestMatrices.matrix([[0]]), deadline: .never)
        #expect(onlyBase.stopOrder.isEmpty)
        #expect(onlyBase.totalDuration == 0)

        let single = try optimizer.solve(RouteTestMatrices.matrix([[0, 4], [6, 0]]), deadline: .never)
        #expect(single.stopOrder == [1])
        #expect(single.totalDuration == 10)
    }

    @Test("Źródło macierzy i powód przybliżenia trafiają do wyniku")
    func carriesCostSource() throws {
        let points = (0..<6).map { Coordinate(latitude: 50 + Double($0) * 0.01, longitude: 19.9) }
        let approximate = HaversineCostProvider.matrix(for: points, reason: .offline)

        let route = try optimizer.solve(approximate, deadline: .never)

        #expect(route.costSource == .approximate)
        #expect(route.isApproximate)
        #expect(route.approximationReason == .offline)
        #expect(try optimizer.solve(RouteTestMatrices.random(count: 6, seed: 1), deadline: .never).costSource == .roadNetwork)
    }

    @Test("Po limicie czasu — najlepsza dotąd poprawna trasa z flagą")
    func timeLimit() throws {
        let matrix = RouteTestMatrices.krakow(count: 150, seed: 8)
        let countdown = CountdownDeadline(checks: 20)

        let route = try optimizer.solve(matrix, deadline: countdown.deadline)

        #expect(route.stoppedByTimeLimit)
        #expect(route.statistics.completedRestarts == 0)
        #expect(RouteTestMatrices.isPermutationOfStops(route.stopOrder, in: matrix))
        #expect(route.totalDuration <= route.statistics.initialDuration)
    }

    @Test("Termin, który już minął — zwraca trasę najbliższego sąsiada")
    func expiredDeadline() throws {
        let matrix = RouteTestMatrices.random(count: 30, seed: 4)
        let route = try optimizer.solve(matrix, deadline: RouteDeadline { true })

        #expect(route.stoppedByTimeLimit)
        #expect(route.totalDuration == route.statistics.initialDuration)
    }

    @Test("Anulowanie zadania przerywa obliczenia błędem CancellationError")
    func cancellation() async {
        let matrix = RouteTestMatrices.krakow(count: 150, seed: 9)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await optimizer.optimize(matrix)
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Wersja async liczy poza głównym wątkiem")
    func runsInBackground() async throws {
        let matrix = RouteTestMatrices.random(count: 20, seed: 2)
        let route = try await optimizer.optimize(matrix)
        #expect(RouteTestMatrices.isPermutationOfStops(route.stopOrder, in: matrix))
        #expect(route == (try optimizer.solve(matrix, deadline: .never)).withElapsed(route.statistics.elapsed))
    }
}

private extension OptimizedRoute {
    /// Kopia z podmienionym czasem obliczeń — do porównań między uruchomieniami.
    func withElapsed(_ elapsed: Duration) -> OptimizedRoute {
        OptimizedRoute(
            stopOrder: stopOrder,
            totalDuration: totalDuration,
            totalDistance: totalDistance,
            costSource: costSource,
            approximationReason: approximationReason,
            stoppedByTimeLimit: stoppedByTimeLimit,
            statistics: .init(
                initialDuration: statistics.initialDuration,
                completedRestarts: statistics.completedRestarts,
                elapsed: elapsed
            )
        )
    }
}
