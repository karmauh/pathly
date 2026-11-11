import Foundation
import Testing
@testable import pathly

@Suite("FallbackCostProvider")
struct FallbackCostProviderTests {
    let points = MatrixFixture.points(4)
    let cache = CostMatrixCache(directory: makeTemporaryDirectory())

    private var roadMatrix: CostMatrix {
        CostMatrix(count: 4, durations: Array(repeating: 1, count: 16), distances: Array(repeating: 2, count: 16), source: .roadNetwork)
    }

    @Test("Bez klucza — przybliżenie z powodem „brak klucza”")
    func missingKey() async throws {
        let matrix = try await FallbackCostProvider(primary: nil, cache: cache).costMatrix(for: points)
        #expect(matrix.source == .approximate)
        #expect(matrix.approximationReason == .missingAPIKey)
        #expect(matrix == HaversineCostProvider.matrix(for: points, reason: .missingAPIKey))
    }

    @Test("Błąd usługi — przybliżenie z właściwym powodem",
          arguments: [
              (TravelCostError.offline, ApproximationReason.offline),
              (.rateLimited, .quotaExhausted),
              (.quotaExhausted, .quotaExhausted),
              (.invalidAPIKey, .invalidAPIKey),
              (.serviceError(statusCode: 500), .serviceError),
              (.invalidResponse, .serviceError),
          ])
    func errorsFallBack(error: TravelCostError, reason: ApproximationReason) async throws {
        let provider = FallbackCostProvider(primary: ScriptedCostProvider(.failure(error)), cache: cache)

        let matrix = try await provider.costMatrix(for: points)

        #expect(matrix.source == .approximate)
        #expect(matrix.approximationReason == reason)
        #expect(await cache.matrix(for: points) == nil, "Przybliżenie nie trafia do pamięci podręcznej")
    }

    @Test("Macierz z sieci dróg jest zapamiętywana — drugie wyliczenie bez zapytań")
    func cachesRoadMatrix() async throws {
        let primary = ScriptedCostProvider(.success(roadMatrix))
        let provider = FallbackCostProvider(primary: primary, cache: cache)

        #expect(try await provider.costMatrix(for: points) == roadMatrix)
        #expect(try await provider.costMatrix(for: points) == roadMatrix)
        #expect(primary.callCount == 1)
    }

    @Test("Anulowanie jest przekazywane dalej, bez przybliżenia")
    func cancellation() async {
        let provider = FallbackCostProvider(primary: ScriptedCostProvider(.failure(CancellationError())), cache: cache)
        await #expect(throws: CancellationError.self) {
            try await provider.costMatrix(for: points)
        }
    }
}
