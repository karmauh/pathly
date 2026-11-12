import Foundation
import Synchronization
import Testing
@testable import pathly

@Suite("RoutePlanner")
struct RoutePlannerTests {
    let base = Coordinate(latitude: 50.06, longitude: 19.94)

    /// Przystanki ułożone na linii na wschód od bazy, wpisane w odwrotnej kolejności.
    private func stops(_ count: Int) -> [RouteStop] {
        (1...count).reversed().map { index in
            RouteStop(parcelID: UUID(), coordinate: Coordinate(latitude: 50.06, longitude: 19.94 + Double(index) * 0.01))
        }
    }

    /// Dostawca, który zapamiętuje punkty i raportuje postęp jak ORS przy 2 zapytaniach.
    final class RecordingProvider: TravelCostProvider {
        let points = Mutex<[Coordinate]>([])
        let reason: ApproximationReason?

        init(reason: ApproximationReason? = nil) {
            self.reason = reason
        }

        func costMatrix(for points: [Coordinate], progress: (@Sendable (MatrixProgress) -> Void)?) async throws -> CostMatrix {
            self.points.withLock { $0 = points }
            progress?(MatrixProgress(completedRequests: 1, totalRequests: 2))
            progress?(MatrixProgress(completedRequests: 2, totalRequests: 2))
            let matrix = HaversineCostProvider.matrix(for: points, reason: reason)
            return reason == nil
                ? CostMatrix(count: matrix.count, durations: matrix.durations, distances: matrix.distances, source: .roadNetwork)
                : matrix
        }
    }

    @Test("Baza jako pierwszy punkt, wynik w identyfikatorach przesyłek w kolejności wzdłuż linii")
    func mapsIndicesToParcels() async throws {
        let stops = stops(4)
        let provider = RecordingProvider()

        let route = try await RoutePlanner(costProvider: provider).plan(base: base, candidates: RouteCandidates(stops: stops))

        #expect(provider.points.withLock { $0 } == [base] + stops.map(\.coordinate))
        // Przystanki leżą na jednej linii: optymalnie tam i z powrotem — od
        // najbliższego do najdalszego albo odwrotnie.
        let nearestFirst = stops.reversed().map(\.parcelID)
        #expect(route.stopOrder == nearestFirst || route.stopOrder == nearestFirst.reversed())
        #expect(route.costSource == .roadNetwork)
        #expect(route.totalDuration > 0 && route.totalDistance > 0)
    }

    @Test("Przybliżona macierz — wynik oznaczony z powodem")
    func approximate() async throws {
        let route = try await RoutePlanner(costProvider: RecordingProvider(reason: .quotaExhausted))
            .plan(base: base, candidates: RouteCandidates(stops: stops(3)))

        #expect(route.costSource == .approximate)
        #expect(route.approximationReason == .quotaExhausted)
    }

    @Test("Postęp: pobieranie macierzy, potem optymalizacja")
    func reportsProgress() async throws {
        let phases = Mutex<[RoutePlanningPhase]>([])
        _ = try await RoutePlanner(costProvider: RecordingProvider()).plan(
            base: base,
            candidates: RouteCandidates(stops: stops(3))
        ) { phase in phases.withLock { $0.append(phase) } }

        #expect(phases.withLock { $0 } == [
            .fetchingMatrix(completedRequests: 0, totalRequests: 0),
            .fetchingMatrix(completedRequests: 1, totalRequests: 2),
            .fetchingMatrix(completedRequests: 2, totalRequests: 2),
            .optimizing,
        ])
    }

    @Test("Blokady przed pierwszym zapytaniem",
          arguments: [
              (false, RouteCandidates(stops: []), RoutePlanningError.missingBase),
              (true, RouteCandidates(stops: []), .noStops),
              (true, RouteCandidates(stops: [RouteStop(parcelID: UUID(), coordinate: .init(latitude: 50, longitude: 20))], needingAttention: 2), .parcelsNeedAttention(count: 2)),
              (true, RouteCandidates(stops: [], awaitingGeocoding: 1), .parcelsAwaitingGeocoding(count: 1)),
          ])
    func blocked(hasBase: Bool, candidates: RouteCandidates, error: RoutePlanningError) async {
        let provider = RecordingProvider()
        await #expect(throws: error) {
            try await RoutePlanner(costProvider: provider).plan(base: hasBase ? base : nil, candidates: candidates)
        }
        #expect(provider.points.withLock { $0 }.isEmpty, "Bez zapytania do usługi tras")
    }

    @Test("Komunikaty blokad po polsku")
    func messages() {
        #expect(RoutePlanningError.missingBase.errorDescription?.contains("bazę") == true)
        #expect(RoutePlanningError.parcelsNeedAttention(count: 1).errorDescription?.hasPrefix("1 przesyłka") == true)
        #expect(RoutePlanningError.parcelsNeedAttention(count: 3).errorDescription?.contains("3") == true)
    }

    @Test("Anulowanie przerywa wyliczanie")
    func cancellation() async {
        let planner = RoutePlanner(costProvider: RecordingProvider())
        let candidates = RouteCandidates(stops: stops(5))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await planner.plan(base: base, candidates: candidates)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
