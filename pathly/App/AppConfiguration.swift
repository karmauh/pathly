import Foundation

/// Konfiguracja aplikacji odczytywana z `Info.plist`.
///
/// Wartości trafiają do `Info.plist` w czasie budowania z plików `.xcconfig`
/// (`Config/Base.xcconfig` → `Config/Secrets.xcconfig`), dzięki czemu klucz
/// API nigdy nie jest zapisany w repozytorium.
///
/// Typ jest `nonisolated`, bo w projekcie domyślną izolacją jest `MainActor`,
/// a niezmienna konfiguracja może być bezpiecznie czytana z dowolnego wątku.
nonisolated struct AppConfiguration: Sendable, Equatable {
    /// Klucz OpenRouteService albo `nil`, gdy nie został skonfigurowany.
    let openRouteServiceAPIKey: String?

    init(infoDictionary: [String: Any]) {
        let rawKey = (infoDictionary["ORSAPIKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Pusta wartość albo nierozwinięta zmienna oznaczają brak klucza.
        if let rawKey, !rawKey.isEmpty, !rawKey.hasPrefix("$(") {
            openRouteServiceAPIKey = rawKey
        } else {
            openRouteServiceAPIKey = nil
        }
    }

    /// Konfiguracja z głównego pakietu aplikacji.
    static var main: AppConfiguration {
        AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }
}
