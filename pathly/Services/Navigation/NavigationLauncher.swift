import Foundation
import UIKit

/// Aplikacja, w której kurier prowadzi nawigację do przystanku.
nonisolated enum NavigationApp: String, CaseIterable, Identifiable, Sendable {
    case appleMaps
    case googleMaps

    /// Klucz ustawienia w `UserDefaults` (`@AppStorage`).
    static let storageKey = "navigationApp"

    var id: Self { self }

    var title: String {
        switch self {
        case .appleMaps: "Mapy Apple"
        case .googleMaps: "Mapy Google"
        }
    }

    /// Czy aplikacja przyjmuje w linku kilka przystanków naraz.
    var supportsMultipleStops: Bool {
        self == .googleMaps
    }
}

/// Adresy URL otwierające trasę samochodem. Start to zawsze bieżące położenie
/// kuriera — ustala je aplikacja nawigacyjna.
///
/// Oba adresy to zwykłe linki `https`: iOS otwiera je w aplikacji Mapy Apple
/// albo Mapy Google (jeśli jest zainstalowana), a w przeciwnym razie w przeglądarce.
nonisolated enum NavigationURLBuilder {
    /// Trasa do jednego punktu.
    static func url(for app: NavigationApp, destination: Coordinate) -> URL {
        switch app {
        case .appleMaps:
            url("https://maps.apple.com/", [("daddr", coordinateText(destination)), ("dirflg", "d")])
        case .googleMaps:
            googleURL(destination: destination, waypoints: [])
        }
    }

    /// Trasa w Mapach Google przez kolejne przystanki partii, na końcu
    /// ewentualnie z powrotem do bazy.
    static func googleRouteURL(for batch: NavigationBatch) -> URL {
        precondition(!batch.stops.isEmpty, "Partia musi zawierać przystanek")
        let points = batch.stops + (batch.base.map { [$0] } ?? [])
        return googleURL(destination: points[points.count - 1], waypoints: Array(points.dropLast()))
    }

    /// Współrzędne zawsze z kropką dziesiętną, niezależnie od ustawień regionalnych.
    static func coordinateText(_ coordinate: Coordinate) -> String {
        let style = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
            .precision(.fractionLength(6))
            .grouping(.never)
        return "\(coordinate.latitude.formatted(style)),\(coordinate.longitude.formatted(style))"
    }

    private static func googleURL(destination: Coordinate, waypoints: [Coordinate]) -> URL {
        var query = [("api", "1"), ("destination", coordinateText(destination))]
        if !waypoints.isEmpty {
            query.append(("waypoints", waypoints.map(coordinateText).joined(separator: "|")))
        }
        query.append(("travelmode", "driving"))
        return url("https://www.google.com/maps/dir/", query)
    }

    private static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}

/// Otwiera nawigację w wybranej aplikacji.
struct NavigationLauncher {
    var open: (URL) -> Void = { UIApplication.shared.open($0) }

    /// Nawigacja do jednego przystanku.
    func navigate(to destination: Coordinate, using app: NavigationApp) {
        open(NavigationURLBuilder.url(for: app, destination: destination))
    }

    /// Nawigacja przez partię przystanków. Mapy Apple nie mają linku z wieloma
    /// przystankami, więc dostają tylko pierwszy z nich.
    func navigate(through batch: NavigationBatch, using app: NavigationApp) {
        guard let first = batch.stops.first else { return }
        if app.supportsMultipleStops {
            open(NavigationURLBuilder.googleRouteURL(for: batch))
        } else {
            navigate(to: first, using: app)
        }
    }
}
