import Foundation
import Testing
@testable import pathly

@Suite("CostMatrixCache")
struct CostMatrixCacheTests {
    let directory = makeTemporaryDirectory()
    let points = MatrixFixture.points(3)

    private func roadMatrix(_ count: Int = 3, scale: Double = 1) -> CostMatrix {
        let values = (0..<(count * count)).map { Double($0) * scale }
        return CostMatrix(count: count, durations: values, distances: values, source: .roadNetwork)
    }

    @Test("Zapisana macierz jest zwracana dla tych samych punktów")
    func hit() async {
        let cache = CostMatrixCache(directory: directory)
        #expect(await cache.matrix(for: points) == nil)

        await cache.store(roadMatrix(), for: points)

        #expect(await cache.matrix(for: points) == roadMatrix())
    }

    @Test("Zmiana punktu lub kolejności — brak trafienia; drobny szum współrzędnych — trafienie")
    func keySensitivity() async {
        let cache = CostMatrixCache(directory: directory)
        await cache.store(roadMatrix(), for: points)

        var moved = points
        moved[1].latitude += 0.001
        #expect(await cache.matrix(for: moved) == nil)
        #expect(await cache.matrix(for: points.reversed()) == nil)

        var jittered = points
        jittered[1].longitude += 0.000_000_1
        #expect(await cache.matrix(for: jittered) != nil)
    }

    @Test("Macierz przetrwa ponowne uruchomienie aplikacji")
    func persists() async {
        await CostMatrixCache(directory: directory).store(roadMatrix(), for: points)

        let reopened = CostMatrixCache(directory: directory)
        #expect(await reopened.matrix(for: points) == roadMatrix())
    }

    @Test("Przybliżenia nie są zapisywane")
    func approximateNotStored() async {
        let cache = CostMatrixCache(directory: directory)
        await cache.store(HaversineCostProvider.matrix(for: points, reason: .offline), for: points)
        #expect(await cache.matrix(for: points) == nil)
    }

    @Test("Najdawniej używana macierz wypada po przekroczeniu pojemności")
    func evictsLeastRecentlyUsed() async {
        let cache = CostMatrixCache(directory: directory, capacity: 2)
        let a = MatrixFixture.points(2)
        let b = MatrixFixture.points(3)
        let c = MatrixFixture.points(4)
        await cache.store(roadMatrix(2), for: a)
        await cache.store(roadMatrix(3), for: b)
        _ = await cache.matrix(for: a)  // „a” używane ostatnio
        await cache.store(roadMatrix(4), for: c)

        #expect(await cache.matrix(for: a) != nil)
        #expect(await cache.matrix(for: b) == nil)
        #expect(await cache.matrix(for: c) != nil)
    }
}
