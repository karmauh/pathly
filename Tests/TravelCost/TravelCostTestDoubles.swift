import Foundation
import Synchronization
@testable import pathly

/// Punkty testowe, z których współrzędnych da się odczytać indeks punktu —
/// atrapa usługi wie dzięki temu, o które komórki pełnej macierzy pytamy.
enum MatrixFixture {
    static func points(_ count: Int) -> [Coordinate] {
        (0..<count).map { Coordinate(latitude: 50 + Double($0) * 0.001, longitude: 19.9 + Double($0) * 0.0005) }
    }

    static func index(of coordinate: Coordinate) -> Int {
        Int(((coordinate.latitude - 50) * 1000).rounded())
    }

    /// „Prawdziwy” czas przejazdu — celowo asymetryczny (A→B ≠ B→A).
    static func duration(_ from: Int, _ to: Int) -> Double {
        Double(from * 1000 + to) + 0.5
    }

    static func distance(_ from: Int, _ to: Int) -> Double {
        Double(from * 1000 + to) * 10 + 0.25
    }
}

/// Atrapa OpenRouteService: odczytuje ciało zapytania i odpowiada fragmentem
/// macierzy z `MatrixFixture`, tak jak zrobiłaby to prawdziwa usługa.
final class StubMatrixTransport: HTTPTransport {
    struct SentRequest {
        let request: URLRequest
        let locations: [Coordinate]
        let sources: [Int]
        let destinations: [Int]

        var pairCount: Int { sources.count * destinations.count }
    }

    private struct State {
        var sent: [SentRequest] = []
        var statusCodes: [Int] = []
        var nullPairs: Set<[Int]> = []
        var error: URLError?
    }

    private let state = Mutex(State())

    var sent: [SentRequest] { state.withLock { $0.sent } }

    /// Kody HTTP dla kolejnych zapytań (potem 200).
    func respond(withStatusCodes codes: [Int]) {
        state.withLock { $0.statusCodes = codes }
    }

    /// Pary [z, do] (indeksy globalne), dla których usługa „nie zna drogi”.
    func noRoute(between pairs: Set<[Int]>) {
        state.withLock { $0.nullPairs = pairs }
    }

    func fail(with error: URLError) {
        state.withLock { $0.error = error }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
        let locations = (body["locations"] as! [[Double]]).map { Coordinate(latitude: $0[1], longitude: $0[0]) }
        let sources = body["sources"] as! [Int]
        let destinations = body["destinations"] as! [Int]

        let (status, nullPairs, error) = state.withLock { state in
            state.sent.append(SentRequest(request: request, locations: locations, sources: sources, destinations: destinations))
            let status = state.statusCodes.isEmpty ? 200 : state.statusCodes.removeFirst()
            return (status, state.nullPairs, state.error)
        }
        if let error { throw error }

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        guard status == 200 else { return (Data(#"{"error":"stub"}"#.utf8), response) }

        func cells(_ value: (Int, Int) -> Double) -> [[Double?]] {
            sources.map { source in
                destinations.map { destination in
                    let from = MatrixFixture.index(of: locations[source])
                    let to = MatrixFixture.index(of: locations[destination])
                    return nullPairs.contains([from, to]) ? nil : value(from, to)
                }
            }
        }
        let json: [String: Any] = [
            "durations": cells(MatrixFixture.duration).map { $0.map { $0 ?? NSNull() as Any } },
            "distances": cells(MatrixFixture.distance).map { $0.map { $0 ?? NSNull() as Any } },
        ]
        return (try JSONSerialization.data(withJSONObject: json), response)
    }
}

/// Zegar sterowany przez test; „czekanie” tylko przesuwa czas.
final class FakeClock: Sendable {
    private let state = Mutex((date: Date(timeIntervalSince1970: 1_800_000_000), sleeps: [Duration]()))

    var now: Date { state.withLock { $0.date } }
    var sleeps: [Duration] { state.withLock { $0.sleeps } }

    func advance(by seconds: TimeInterval) {
        state.withLock { $0.date += seconds }
    }

    func sleep(_ duration: Duration) {
        state.withLock {
            $0.sleeps.append(duration)
            $0.date += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
    }
}

/// Dzienny licznik w pamięci.
final class InMemoryDailyUsageStore: DailyUsageStore {
    private let usage = Mutex<DailyUsage?>(nil)

    var current: DailyUsage? { usage.withLock { $0 } }

    func load() -> DailyUsage? { usage.withLock { $0 } }
    func save(_ newValue: DailyUsage) { usage.withLock { $0 = newValue } }
}

/// Dostawca, który zawsze zgłasza dany błąd albo zwraca daną macierz.
final class ScriptedCostProvider: TravelCostProvider {
    private let result: Result<CostMatrix, any Error>
    private let calls = Mutex(0)

    var callCount: Int { calls.withLock { $0 } }

    init(_ result: Result<CostMatrix, any Error>) {
        self.result = result
    }

    func costMatrix(for points: [Coordinate], progress: (@Sendable (MatrixProgress) -> Void)?) async throws -> CostMatrix {
        calls.withLock { $0 += 1 }
        return try result.get()
    }
}

extension RequestRateLimiter {
    /// Limiter z zegarem testowym i licznikiem w pamięci.
    static func test(
        clock: FakeClock = FakeClock(),
        usage: InMemoryDailyUsageStore = InMemoryDailyUsageStore(),
        limits: Limits = Limits()
    ) -> RequestRateLimiter {
        RequestRateLimiter(limits: limits, usageStore: usage, now: { clock.now }, sleep: { clock.sleep($0) })
    }
}

/// Nowy pusty katalog tymczasowy dla jednego testu.
func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "pathly-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}
