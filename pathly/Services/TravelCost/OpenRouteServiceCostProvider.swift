import Foundation

/// Macierz czasów i odległości z sieci dróg (OpenRouteService).
///
/// Duże macierze dzielone są na bloki mieszczące się w limicie par
/// (`MatrixBlockPlanner`), a bloki pobierane po kolei przez `RequestRateLimiter`.
/// Pary, dla których usługa nie znalazła drogi, uzupełniamy przybliżeniem.
nonisolated struct OpenRouteServiceCostProvider: TravelCostProvider {
    let client: OpenRouteServiceClient
    let limiter: RequestRateLimiter
    var maxPairsPerRequest = MatrixBlockPlanner.maxPairsPerRequest
    /// Opóźnienia ponowień po błędzie 429 (limiter powinien mu zapobiegać, ale
    /// z tego samego klucza mogą korzystać inne urządzenia).
    var rateLimitRetryDelays: [Duration] = [.seconds(5), .seconds(15)]
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func costMatrix(
        for points: [Coordinate],
        progress: (@Sendable (MatrixProgress) -> Void)?
    ) async throws -> CostMatrix {
        let count = points.count
        guard count > 1 else {
            return CostMatrix(count: count, durations: [Double](repeating: 0, count: count),
                              distances: [Double](repeating: 0, count: count), source: .roadNetwork)
        }

        let blocks = MatrixBlockPlanner.blocks(pointCount: count, maxPairs: maxPairsPerRequest)
        // Nie zaczynamy, jeśli limit skończy się w połowie — zmarnowalibyśmy zapytania.
        guard await limiter.remainingToday() >= blocks.count else {
            throw TravelCostError.quotaExhausted
        }

        var durations = [Double?](repeating: nil, count: count * count)
        var distances = [Double?](repeating: nil, count: count * count)
        progress?(MatrixProgress(completedRequests: 0, totalRequests: blocks.count))

        for (index, block) in blocks.enumerated() {
            try Task.checkCancellation()
            let response = try await fetch(block, points: points)
            for (row, from) in block.sources.enumerated() {
                for (column, to) in block.destinations.enumerated() {
                    durations[from * count + to] = response.durations[row][column]
                    distances[from * count + to] = response.distances[row][column]
                }
            }
            progress?(MatrixProgress(completedRequests: index + 1, totalRequests: blocks.count))
        }

        return Self.assemble(points: points, durations: durations, distances: distances)
    }

    /// Pobiera jeden blok. Wysyłamy tylko punkty, których blok dotyczy — przy
    /// typowym podziale (wszyscy odbiorcy) to i tak wszystkie punkty.
    private func fetch(_ block: MatrixBlock, points: [Coordinate]) async throws -> MatrixResponse {
        let involved = Array(Set(block.sources).union(block.destinations)).sorted()
        let position = Dictionary(uniqueKeysWithValues: involved.enumerated().map { ($1, $0) })
        let locations = involved.map { points[$0] }
        let sources = block.sources.map { position[$0]! }
        let destinations = block.destinations.map { position[$0]! }

        var retries = rateLimitRetryDelays[...]
        while true {
            try await limiter.acquire()
            do {
                return try await client.matrix(locations: locations, sources: sources, destinations: destinations)
            } catch TravelCostError.rateLimited {
                guard let delay = retries.popFirst() else { throw TravelCostError.rateLimited }
                try await sleep(delay)
            }
        }
    }

    /// Składa macierz; brakujące pary (brak drogi) i przekątną uzupełnia.
    static func assemble(points: [Coordinate], durations: [Double?], distances: [Double?]) -> CostMatrix {
        let count = points.count
        var finalDurations = [Double](repeating: 0, count: count * count)
        var finalDistances = [Double](repeating: 0, count: count * count)
        var estimated = 0
        for from in 0..<count {
            for to in 0..<count where from != to {
                let index = from * count + to
                if let duration = durations[index], let distance = distances[index] {
                    finalDurations[index] = duration
                    finalDistances[index] = distance
                } else {
                    let distance = HaversineCostProvider.estimatedDistance(from: points[from], to: points[to])
                    finalDistances[index] = distance
                    finalDurations[index] = HaversineCostProvider.estimatedDuration(forDistance: distance)
                    estimated += 1
                }
            }
        }
        return CostMatrix(
            count: count,
            durations: finalDurations,
            distances: finalDistances,
            source: .roadNetwork,
            estimatedPairCount: estimated
        )
    }
}
