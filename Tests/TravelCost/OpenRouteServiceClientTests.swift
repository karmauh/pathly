import Foundation
import Testing
@testable import pathly

@Suite("OpenRouteServiceClient")
struct OpenRouteServiceClientTests {
    let transport = StubMatrixTransport()
    var client: OpenRouteServiceClient { OpenRouteServiceClient(apiKey: "test-key", transport: transport) }
    let points = MatrixFixture.points(3)

    @Test("Zapytanie: POST z kluczem, punkty jako [długość, szerokość], obie metryki")
    func requestShape() throws {
        let request = try client.makeRequest(locations: points, sources: [0, 1], destinations: [0, 1, 2])

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openrouteservice.org/v2/matrix/driving-car")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true)

        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let locations = try #require(body["locations"] as? [[Double]])
        #expect(locations.first == [points[0].longitude, points[0].latitude])
        #expect(body["sources"] as? [Int] == [0, 1])
        #expect(body["destinations"] as? [Int] == [0, 1, 2])
        #expect(body["metrics"] as? [String] == ["duration", "distance"])
        #expect(body["units"] as? String == "m")
    }

    @Test("Odpowiedź z brakującymi drogami (null) jest odczytywana")
    func decodesNulls() async throws {
        transport.noRoute(between: [[0, 2]])

        let response = try await client.matrix(locations: points, sources: [0, 1], destinations: [0, 1, 2])

        #expect(response.durations == [[0.5, 1.5, nil], [1000.5, 1001.5, 1002.5]])
        #expect(response.distances[1][0] == MatrixFixture.distance(1, 0))
        #expect(response.distances[0][2] == nil)
    }

    @Test("Kody HTTP zamieniane na błędy",
          arguments: [(401, TravelCostError.invalidAPIKey), (403, .invalidAPIKey), (429, .rateLimited), (500, .serviceError(statusCode: 500))])
    func statusCodes(code: Int, expected: TravelCostError) async {
        transport.respond(withStatusCodes: [code])
        await #expect(throws: expected) {
            try await client.matrix(locations: points, sources: [0], destinations: [0, 1])
        }
    }

    @Test("Brak sieci → offline")
    func offline() async {
        transport.fail(with: URLError(.notConnectedToInternet))
        await #expect(throws: TravelCostError.offline) {
            try await client.matrix(locations: points, sources: [0], destinations: [0])
        }
    }

    @Test("Anulowane zapytanie to anulowanie, nie błąd usługi")
    func cancelled() async {
        transport.fail(with: URLError(.cancelled))
        await #expect(throws: CancellationError.self) {
            try await client.matrix(locations: points, sources: [0], destinations: [0])
        }
    }

    @Test("Odpowiedź o złym kształcie → invalidResponse")
    func wrongShape() async {
        let wrongShape = WrongShapeTransport()
        let client = OpenRouteServiceClient(apiKey: "k", transport: wrongShape)
        await #expect(throws: TravelCostError.invalidResponse) {
            try await client.matrix(locations: points, sources: [0, 1], destinations: [0, 1])
        }
    }

    /// Zwraca jeden wiersz zamiast dwóch.
    struct WrongShapeTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let data = Data(#"{"durations":[[0,1]],"distances":[[0,1]]}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}
