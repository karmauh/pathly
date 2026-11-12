import Foundation
import Testing
@testable import pathly

/// Kryterium etapu 6: dla 150 punktów (baza i 149 przystanków) wynik w czasie
/// poniżej 2 s.
///
/// Mierzymy czas procesora wątku, który liczy trasę, a nie czas zegarowy:
/// testy działają równolegle (np. OCR Vision obciąża wszystkie rdzenie),
/// więc czas zegarowy mierzyłby obciążenie symulatora, a nie algorytm.
/// Testy działają w buildzie Debug (bez optymalizacji kompilatora), więc są
/// wolniejsze od wersji Release na iPhonie — przejście tutaj daje zapas.
@Suite("Wydajność algorytmu trasy", .serialized)
struct RoutePerformanceTests {
    @Test("150 punktów poniżej 2 s czasu procesora — przeszukiwanie kończy się samo, bez limitu czasu",
          arguments: [1, 2, 3] as [UInt64])
    func hundredFiftyPoints(seed: UInt64) throws {
        let matrix = RouteTestMatrices.krakow(count: 150, seed: seed)
        let optimizer = RouteOptimizer()

        let started = Self.threadCPUTime()
        let route = try optimizer.solve(matrix, deadline: .never)
        let cpuTime = Self.threadCPUTime() - started

        #expect(cpuTime < .seconds(2))
        #expect(route.statistics.completedRestarts == optimizer.configuration.restarts)
        #expect(RouteTestMatrices.isPermutationOfStops(route.stopOrder, in: matrix))

        let improvement = (1 - route.totalDuration / route.statistics.initialDuration) * 100
        Attachment.record("150 punktów (seed \(seed)): \(cpuTime.formatted(.units(allowed: [.milliseconds]))) CPU, \(route.statistics.elapsed.formatted(.units(allowed: [.milliseconds]))) zegarowo, poprawa względem najbliższego sąsiada \(improvement.formatted(.number.precision(.fractionLength(1)))) %, \((route.totalDuration / 60).formatted(.number.precision(.fractionLength(0)))) min", named: "statystyki.txt")
    }

    @Test("150 punktów w tle z limitem 2 s — zawsze poprawna trasa")
    func hundredFiftyPointsInBackground() async throws {
        let matrix = RouteTestMatrices.krakow(count: 150, seed: 4)
        let route = try await RouteOptimizer().optimize(matrix)

        #expect(RouteTestMatrices.isPermutationOfStops(route.stopOrder, in: matrix))
        #expect(route.totalDuration <= route.statistics.initialDuration)
        #expect(route.statistics.elapsed < .seconds(2.5), "Limit czasu przerywa obliczenia niedługo po 2 s")
    }

    /// Czas procesora zużyty przez bieżący wątek.
    private static func threadCPUTime() -> Duration {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return .seconds(time.tv_sec) + .nanoseconds(time.tv_nsec)
    }
}
