import Foundation

/// Wysyłanie zapytań HTTP. W testach zastępowane atrapą — bez prawdziwej sieci.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transport produkcyjny na `URLSession`.
nonisolated struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TravelCostError.invalidResponse
        }
        return (data, http)
    }
}

/// Fragment macierzy zwrócony przez OpenRouteService.
///
/// `nil` w komórce oznacza, że usługa nie znalazła drogi między punktami.
nonisolated struct MatrixResponse: Hashable, Sendable {
    /// Czasy w sekundach, wiersze = nadawcy, kolumny = odbiorcy.
    let durations: [[Double?]]
    /// Odległości w metrach.
    let distances: [[Double?]]
}

/// Klient endpointu macierzy OpenRouteService (`POST /v2/matrix/driving-car`).
///
/// Wykonuje jedno zapytanie — dzielenie na bloki i limity są wyżej, w
/// `OpenRouteServiceCostProvider`.
nonisolated struct OpenRouteServiceClient: Sendable {
    static let endpoint = URL(string: "https://api.openrouteservice.org/v2/matrix/driving-car")!

    let apiKey: String
    let transport: any HTTPTransport

    init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    /// Pobiera macierz dla nadawców `sources` i odbiorców `destinations`
    /// (indeksy w `locations`).
    func matrix(locations: [Coordinate], sources: [Int], destinations: [Int]) async throws -> MatrixResponse {
        let request = try makeRequest(locations: locations, sources: sources, destinations: destinations)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw TravelCostError.offline
        }

        switch response.statusCode {
        case 200..<300:
            return try decode(data, rows: sources.count, columns: destinations.count)
        case 401, 403:
            throw TravelCostError.invalidAPIKey
        case 429:
            throw TravelCostError.rateLimited
        default:
            throw TravelCostError.serviceError(statusCode: response.statusCode)
        }
    }

    func makeRequest(locations: [Coordinate], sources: [Int], destinations: [Int]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            // OpenRouteService oczekuje kolejności [długość, szerokość].
            locations: locations.map { [$0.longitude, $0.latitude] },
            sources: sources,
            destinations: destinations,
            metrics: ["duration", "distance"],
            units: "m"
        ))
        return request
    }

    private func decode(_ data: Data, rows: Int, columns: Int) throws -> MatrixResponse {
        guard let body = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let durations = body.durations,
              let distances = body.distances,
              Self.hasShape(durations, rows: rows, columns: columns),
              Self.hasShape(distances, rows: rows, columns: columns)
        else {
            throw TravelCostError.invalidResponse
        }
        return MatrixResponse(durations: durations, distances: distances)
    }

    private static func hasShape(_ matrix: [[Double?]], rows: Int, columns: Int) -> Bool {
        matrix.count == rows && matrix.allSatisfy { $0.count == columns }
    }

    private struct RequestBody: Encodable {
        let locations: [[Double]]
        let sources: [Int]
        let destinations: [Int]
        let metrics: [String]
        let units: String
    }

    private struct ResponseBody: Decodable {
        let durations: [[Double?]]?
        let distances: [[Double?]]?
    }
}
