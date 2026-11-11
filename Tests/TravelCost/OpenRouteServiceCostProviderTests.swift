import Foundation
import Synchronization
import Testing
@testable import pathly

@Suite("OpenRouteServiceCostProvider")
struct OpenRouteServiceCostProviderTests {
    let transport = StubMatrixTransport()
    let clock = FakeClock()
    let usage = InMemoryDailyUsageStore()

    private func makeProvider(limits: RequestRateLimiter.Limits = .init()) -> OpenRouteServiceCostProvider {
        let clock = clock
        return OpenRouteServiceCostProvider(
            client: OpenRouteServiceClient(apiKey: "k", transport: transport),
            limiter: .test(clock: clock, usage: usage, limits: limits),
            sleep: { clock.sleep($0) }
        )
    }

    private func expectMatchesFixture(_ matrix: CostMatrix) {
        var mismatches = 0
        for from in 0..<matrix.count {
            for to in 0..<matrix.count {
                let expectedDuration = from == to ? 0 : MatrixFixture.duration(from, to)
                let expectedDistance = from == to ? 0 : MatrixFixture.distance(from, to)
                if matrix.duration(from: from, to: to) != expectedDuration
                    || matrix.distance(from: from, to: to) != expectedDistance {
                    mismatches += 1
                }
            }
        }
        #expect(mismatches == 0)
    }

    @Test("Ponad 100 punktów: zapytania w limicie par, pełna i poprawna macierz",
          arguments: [(101, 3), (150, 7)])
    func largeMatrix(pointCount: Int, expectedRequests: Int) async throws {
        let points = MatrixFixture.points(pointCount)

        let matrix = try await makeProvider().costMatrix(for: points)

        #expect(transport.sent.count == expectedRequests)
        #expect(transport.sent.allSatisfy { $0.pairCount <= 3500 })
        #expect(transport.sent.reduce(0) { $0 + $1.pairCount } == pointCount * pointCount)
        #expect(matrix.count == pointCount)
        #expect(matrix.source == .roadNetwork)
        #expect(matrix.estimatedPairCount == 0)
        expectMatchesFixture(matrix)
        #expect(matrix.duration(from: 3, to: 7) != matrix.duration(from: 7, to: 3), "Macierz jest asymetryczna")
        #expect(usage.current?.count == expectedRequests)
    }

    @Test("Postęp po każdym zapytaniu")
    func progress() async throws {
        let reported = Mutex<[MatrixProgress]>([])

        _ = try await makeProvider().costMatrix(for: MatrixFixture.points(101)) { progress in
            reported.withLock { $0.append(progress) }
        }

        #expect(reported.withLock { $0 }.map(\.completedRequests) == [0, 1, 2, 3])
        #expect(reported.withLock { $0 }.allSatisfy { $0.totalRequests == 3 })
    }

    @Test("Pary bez drogi uzupełniane przybliżeniem")
    func missingRoutesAreEstimated() async throws {
        let points = MatrixFixture.points(4)
        transport.noRoute(between: [[1, 3], [3, 1]])

        let matrix = try await makeProvider().costMatrix(for: points)

        let estimate = HaversineCostProvider.estimatedDistance(from: points[1], to: points[3])
        #expect(matrix.distance(from: 1, to: 3) == estimate)
        #expect(matrix.duration(from: 3, to: 1) == HaversineCostProvider.estimatedDuration(forDistance: estimate))
        #expect(matrix.duration(from: 0, to: 2) == MatrixFixture.duration(0, 2))
        #expect(matrix.estimatedPairCount == 2)
        #expect(matrix.source == .roadNetwork)
    }

    @Test("Za mało dziennego limitu — nie zaczynamy pobierania")
    func insufficientQuota() async {
        var limits = RequestRateLimiter.Limits()
        limits.perDay = 2

        await #expect(throws: TravelCostError.quotaExhausted) {
            try await makeProvider(limits: limits).costMatrix(for: MatrixFixture.points(101))
        }
        #expect(transport.sent.isEmpty)
    }

    @Test("Po błędzie 429 czeka i ponawia")
    func retriesAfterRateLimit() async throws {
        transport.respond(withStatusCodes: [429])

        let matrix = try await makeProvider().costMatrix(for: MatrixFixture.points(5))

        #expect(transport.sent.count == 2)
        #expect(clock.sleeps == [.seconds(5)])
        expectMatchesFixture(matrix)
    }

    @Test("Ciągłe 429 — po ponowieniach błąd limitu")
    func persistentRateLimit() async {
        transport.respond(withStatusCodes: [429, 429, 429])

        await #expect(throws: TravelCostError.rateLimited) {
            try await makeProvider().costMatrix(for: MatrixFixture.points(5))
        }
        #expect(transport.sent.count == 3)
        #expect(clock.sleeps == [.seconds(5), .seconds(15)])
    }

    @Test("Limit 40 na minutę — 41. zapytanie czeka")
    func perMinuteLimitAcrossBlocks() async throws {
        // Limit 10 par na zapytanie: 21 punktów → 21 wierszy × 3 bloki odbiorców = 63 zapytania.
        var provider = makeProvider()
        provider.maxPairsPerRequest = 10
        _ = try await provider.costMatrix(for: MatrixFixture.points(21))

        #expect(transport.sent.count == 63)
        #expect(clock.sleeps == [.seconds(60)], "Jedno czekanie na zwolnienie okna — po 40. zapytaniu")
    }

    @Test("Jeden punkt — bez zapytań")
    func singlePoint() async throws {
        let matrix = try await makeProvider().costMatrix(for: MatrixFixture.points(1))
        #expect(matrix.count == 1)
        #expect(transport.sent.isEmpty)
    }
}
