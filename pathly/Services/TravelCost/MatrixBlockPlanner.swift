import Foundation

/// Fragment macierzy pobierany jednym zapytaniem: wiersze `sources` × kolumny `destinations`.
nonisolated struct MatrixBlock: Hashable, Sendable {
    let sources: Range<Int>
    let destinations: Range<Int>

    var pairCount: Int { sources.count * destinations.count }
}

/// Dzieli macierz N×N na bloki mieszczące się w limicie par na zapytanie.
///
/// Blok obejmuje wszystkich odbiorców i tylu nadawców, ilu się zmieści
/// (np. 101 punktów → bloki 34×101, 34×101, 33×101). Dopiero przy N większym
/// niż limit dzielimy też odbiorców. Bloki pokrywają macierz dokładnie raz.
nonisolated enum MatrixBlockPlanner {
    /// Limit darmowego planu OpenRouteService (nadawcy × odbiorcy).
    static let maxPairsPerRequest = 3500

    static func blocks(pointCount: Int, maxPairs: Int = maxPairsPerRequest) -> [MatrixBlock] {
        precondition(maxPairs > 0, "Limit par musi być dodatni")
        guard pointCount > 0 else { return [] }

        let destinationsPerBlock = min(pointCount, maxPairs)
        let sourcesPerBlock = max(1, maxPairs / destinationsPerBlock)

        var blocks: [MatrixBlock] = []
        for sourceStart in stride(from: 0, to: pointCount, by: sourcesPerBlock) {
            let sources = sourceStart..<min(sourceStart + sourcesPerBlock, pointCount)
            for destinationStart in stride(from: 0, to: pointCount, by: destinationsPerBlock) {
                let destinations = destinationStart..<min(destinationStart + destinationsPerBlock, pointCount)
                blocks.append(MatrixBlock(sources: sources, destinations: destinations))
            }
        }
        return blocks
    }
}
