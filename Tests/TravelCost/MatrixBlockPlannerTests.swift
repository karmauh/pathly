import Testing
@testable import pathly

@Suite("MatrixBlockPlanner")
struct MatrixBlockPlannerTests {
    @Test("Każdy blok mieści się w limicie, a bloki pokrywają macierz dokładnie raz",
          arguments: [1, 2, 34, 59, 60, 101, 150, 300])
    func coversMatrixOnce(pointCount: Int) {
        let blocks = MatrixBlockPlanner.blocks(pointCount: pointCount)
        var covered = [Int](repeating: 0, count: pointCount * pointCount)
        for block in blocks {
            #expect(block.pairCount <= MatrixBlockPlanner.maxPairsPerRequest)
            for from in block.sources {
                for to in block.destinations {
                    covered[from * pointCount + to] += 1
                }
            }
        }
        #expect(covered.allSatisfy { $0 == 1 })
    }

    @Test("101 punktów → 3 zapytania po 34, 34 i 33 nadawców")
    func hundredAndOne() {
        let blocks = MatrixBlockPlanner.blocks(pointCount: 101)
        #expect(blocks.map(\.sources.count) == [34, 34, 33])
        #expect(blocks.allSatisfy { $0.destinations == 0..<101 })
        #expect(blocks.map(\.pairCount) == [3434, 3434, 3333])
    }

    @Test("150 punktów → 7 zapytań po 23 nadawców (ostatnie 12)")
    func hundredAndFifty() {
        let blocks = MatrixBlockPlanner.blocks(pointCount: 150)
        #expect(blocks.count == 7)
        #expect(blocks.map(\.sources.count) == [23, 23, 23, 23, 23, 23, 12])
    }

    @Test("Mała macierz mieści się w jednym zapytaniu")
    func singleRequest() {
        #expect(MatrixBlockPlanner.blocks(pointCount: 59) == [MatrixBlock(sources: 0..<59, destinations: 0..<59)])
    }

    @Test("Ponad 3500 punktów — dzielimy też odbiorców")
    func splitsDestinations() {
        let blocks = MatrixBlockPlanner.blocks(pointCount: 5000)
        #expect(blocks.allSatisfy { $0.pairCount <= 3500 && $0.sources.count == 1 })
        #expect(blocks.reduce(0) { $0 + $1.pairCount } == 5000 * 5000)
        #expect(blocks.prefix(2).map(\.destinations) == [0..<3500, 3500..<5000])
    }

    @Test("Brak punktów — brak zapytań")
    func empty() {
        #expect(MatrixBlockPlanner.blocks(pointCount: 0).isEmpty)
    }
}
