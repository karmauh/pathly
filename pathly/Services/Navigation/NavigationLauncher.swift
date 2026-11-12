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
}

/// Adresy URL otwierające trasę samochodem do wskazanego punktu.
nonisolated enum NavigationURLBuilder {
    /// Adres aplikacji. Mapy Apple obsługują link `maps.apple.com` zawsze;
    /// Mapy Google — schemat `comgooglemaps://`, o ile są zainstalowane.
    static func appURL(for app: NavigationApp, destination: Coordinate) -> URL {
        switch app {
        case .appleMaps:
            url("https://maps.apple.com/", ["daddr": coordinateText(destination), "dirflg": "d"])
        case .googleMaps:
            url("comgooglemaps://", ["daddr": coordinateText(destination), "directionsmode": "driving"])
        }
    }

    /// Mapy Google w przeglądarce — gdy aplikacji nie ma na telefonie.
    static func googleWebURL(destination: Coordinate) -> URL {
        url("https://www.google.com/maps/dir/", ["api": "1", "destination": coordinateText(destination), "travelmode": "driving"])
    }

    /// Współrzędne zawsze z kropką dziesiętną, niezależnie od ustawień regionalnych.
    static func coordinateText(_ coordinate: Coordinate) -> String {
        let style = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
            .precision(.fractionLength(6))
            .grouping(.never)
        return "\(coordinate.latitude.formatted(style)),\(coordinate.longitude.formatted(style))"
    }

    private static func url(_ base: String, _ query: KeyValuePairs<String, String>) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
}

/// Otwiera nawigację do przystanku w wybranej aplikacji.
struct NavigationLauncher {
    var canOpen: (URL) -> Bool = { UIApplication.shared.canOpenURL($0) }
    var open: (URL) -> Void = { UIApplication.shared.open($0) }

    /// Adres, który zostanie otwarty — z rezerwą na Mapy Google w przeglądarce.
    func url(for app: NavigationApp, destination: Coordinate) -> URL {
        let appURL = NavigationURLBuilder.appURL(for: app, destination: destination)
        if app == .googleMaps, !canOpen(appURL) {
            return NavigationURLBuilder.googleWebURL(destination: destination)
        }
        return appURL
    }

    func navigate(to destination: Coordinate, using app: NavigationApp) {
        open(url(for: app, destination: destination))
    }
}
