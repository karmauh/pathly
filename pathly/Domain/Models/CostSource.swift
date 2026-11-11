import Foundation

/// Źródło macierzy kosztów, na której policzono trasę.
nonisolated enum CostSource: String, Codable, Sendable {
    /// Rzeczywiste czasy przejazdu z OpenRouteService.
    case roadNetwork
    /// Przybliżenie z odległości w linii prostej (haversine).
    case approximate
}
