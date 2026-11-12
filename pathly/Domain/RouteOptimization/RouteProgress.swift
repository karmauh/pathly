import Foundation

/// Stan realizacji trasy: kolejne przystanki, ich statusy i bieżący przystanek.
///
/// Liczony z kolejności zapisanej trasy i statusów przesyłek — bez SwiftData,
/// więc da się go przetestować. Przesyłki usunięte po wyliczeniu trasy są
/// pomijane (trasa jest wtedy i tak oznaczona jako nieaktualna).
nonisolated struct RouteProgress: Hashable, Sendable {
    nonisolated struct Entry: Hashable, Identifiable, Sendable {
        /// Numer przystanku na trasie, od 1.
        let number: Int
        let parcelID: UUID
        let status: DeliveryStatus

        var id: UUID { parcelID }
    }

    let entries: [Entry]

    init(stopOrder: [UUID], statuses: [UUID: DeliveryStatus]) {
        entries = stopOrder
            .compactMap { id in statuses[id].map { (id, $0) } }
            .enumerated()
            .map { Entry(number: $0.offset + 1, parcelID: $0.element.0, status: $0.element.1) }
    }

    /// Następny przystanek do obsłużenia — pierwszy niezrealizowany w kolejności.
    var current: Entry? {
        entries.first { $0.status == .pending }
    }

    var deliveredCount: Int { entries.count { $0.status == .delivered } }
    var notDeliveredCount: Int { entries.count { $0.status == .notDelivered } }
    var completedCount: Int { deliveredCount + notDeliveredCount }
    var isFinished: Bool { !entries.isEmpty && current == nil }
}
