import Foundation
import Synchronization
import Testing
@testable import pathly

/// Test na prawdziwej usłudze OpenRouteService — kryterium etapu 5.
///
/// Uruchamia się tylko, gdy klucz jest skonfigurowany w `Config/Secrets.xcconfig`.
/// Zużywa 3 zapytania z dziennego limitu (licznik aplikacji to uwzględnia).
@Suite("OpenRouteService (na żywo)", .enabled(if: AppConfiguration.main.openRouteServiceAPIKey != nil, "Brak klucza ORS"))
struct OpenRouteServiceLiveTests {
    /// Liczy wysłane zapytania i ich rozmiar, przekazując je do prawdziwej sieci.
    final class CountingTransport: HTTPTransport {
        private let pairCounts = Mutex<[Int]>([])
        private let real = URLSessionTransport()

        var sentPairCounts: [Int] { pairCounts.withLock { $0 } }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            let pairs = (body["sources"] as! [Int]).count * (body["destinations"] as! [Int]).count
            pairCounts.withLock { $0.append(pairs) }
            return try await real.send(request)
        }
    }

    /// 101 punktów na siatce w centrum Krakowa (ok. 4 × 3 km).
    static let krakowGrid: [Coordinate] = (0..<101).map { index in
        Coordinate(
            latitude: 50.040 + Double(index / 11) * 0.004,
            longitude: 19.900 + Double(index % 11) * 0.006
        )
    }

    @Test("Macierz 101 × 101 pobrana w 3 zapytaniach w limicie 3500 par")
    func matrixForMoreThanHundredPoints() async throws {
        let key = try #require(AppConfiguration.main.openRouteServiceAPIKey)
        let transport = CountingTransport()
        let provider = OpenRouteServiceCostProvider(
            client: OpenRouteServiceClient(apiKey: key, transport: transport),
            limiter: RequestRateLimiter()
        )
        let points = Self.krakowGrid

        let started = ContinuousClock.now
        let matrix = try await provider.costMatrix(for: points)
        let elapsed = ContinuousClock.now - started

        #expect(transport.sentPairCounts == [3434, 3434, 3333])
        #expect(matrix.count == 101)
        #expect(matrix.source == .roadNetwork)
        // Część punktów siatki może wypaść w rzece lub parku, ale zdecydowana
        // większość par musi pochodzić z sieci dróg.
        #expect(matrix.estimatedPairCount < 101 * 100 / 10)

        var asymmetric = 0
        var unrealistic = 0
        for from in 0..<101 {
            for to in 0..<101 where from != to {
                let duration = matrix.duration(from: from, to: to)
                if duration <= 0 || duration > 3600 { unrealistic += 1 }
                if abs(duration - matrix.duration(from: to, to: from)) > 1 { asymmetric += 1 }
            }
        }
        #expect(unrealistic == 0, "Przejazd w centrum Krakowa trwa od kilku sekund do najwyżej godziny")
        #expect(asymmetric > 0, "Ulice jednokierunkowe dają asymetrię")
        print("ORS live: 3 zapytania w \(elapsed), szacowanych par: \(matrix.estimatedPairCount), asymetrycznych: \(asymmetric)")
    }
}
