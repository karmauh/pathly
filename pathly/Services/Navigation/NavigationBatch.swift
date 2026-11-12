import Foundation

/// Kolejne przystanki wysyłane razem do aplikacji nawigacyjnej.
///
/// Mapy Google przyjmują w linku cel i kilka przystanków pośrednich — w praktyce
/// około 10 punktów razem z miejscem startu (bieżącym położeniem). Dlatego trasa
/// jest wysyłana partiami: od bieżącego przystanku do 9 kolejnych
/// niezrealizowanych, a gdy zostało ich najwyżej 8 — z powrotem do bazy na końcu.
/// Po obsłużeniu partii kolejne naciśnięcie wysyła następną.
nonisolated struct NavigationBatch: Hashable, Sendable {
    /// Najwięcej punktów (przystanki i ewentualnie baza) w jednym linku.
    static let maxPoints = 9

    /// Przesyłki w kolejności trasy.
    let parcelIDs: [UUID]
    let stops: [Coordinate]
    /// Baza jako ostatni punkt — gdy partia obejmuje wszystkie pozostałe przystanki.
    let base: Coordinate?

    var returnsToBase: Bool { base != nil }

    /// Partia od bieżącego (pierwszego niezrealizowanego) przystanku.
    /// `nil`, gdy nie ma już nic do doręczenia.
    static func next(
        in progress: RouteProgress,
        coordinates: [UUID: Coordinate],
        base: Coordinate?,
        maxPoints: Int = maxPoints
    ) -> NavigationBatch? {
        let pending = progress.entries
            .filter { $0.status == .pending }
            .compactMap { entry in coordinates[entry.parcelID].map { (entry.parcelID, $0) } }
        guard !pending.isEmpty else { return nil }

        let fitsWithBase = base != nil && pending.count < maxPoints
        let batch = pending.prefix(fitsWithBase ? pending.count : maxPoints)
        return NavigationBatch(
            parcelIDs: batch.map(\.0),
            stops: batch.map(\.1),
            base: fitsWithBase ? base : nil
        )
    }
}

nonisolated extension NavigationBatch {
    /// Opis partii dla kuriera, np. „Mapy Google poprowadzą przez 9 kolejnych przystanków.”
    static func description(of batch: NavigationBatch) -> String {
        let stops = stopCountText(batch.stops.count)
        return batch.returnsToBase
            ? "Mapy Google poprowadzą przez \(stops) i z powrotem do bazy."
            : "Mapy Google poprowadzą przez \(stops). Po ich obsłużeniu naciśnij ponownie, aby wysłać kolejne."
    }

    /// „ostatni przystanek”, „3 kolejne przystanki”, „9 kolejnych przystanków”.
    /// Wystarcza dla 1…9 — więcej przystanków nie mieści się w partii.
    static func stopCountText(_ count: Int) -> String {
        switch count {
        case 1: "ostatni przystanek"
        case 2...4: "\(count) kolejne przystanki"
        default: "\(count) kolejnych przystanków"
        }
    }
}
