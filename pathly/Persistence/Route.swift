import Foundation
import SwiftData

/// Wyliczona trasa (model SwiftData). Aplikacja przechowuje tylko bieżącą —
/// pilnuje tego `SwiftDataRouteStore`.
@Model
final class Route {
    var createdAt: Date
    /// Identyfikatory przesyłek w kolejności doręczeń (bez bazy na początku i końcu).
    var stopOrder: [UUID]
    /// Szacowany łączny czas przejazdu w sekundach.
    var totalDuration: TimeInterval
    /// Szacowany łączny dystans w metrach.
    var totalDistance: Double
    var costSource: CostSource
    /// Dlaczego trasa jest przybliżona — komunikat przetrwa ponowne uruchomienie.
    var approximationReason: ApproximationReason?
    /// `false`, gdy po wyliczeniu dodano lub usunięto przesyłkę.
    var isUpToDate: Bool

    init(
        createdAt: Date = .now,
        stopOrder: [UUID],
        totalDuration: TimeInterval,
        totalDistance: Double,
        costSource: CostSource,
        approximationReason: ApproximationReason? = nil
    ) {
        self.createdAt = createdAt
        self.stopOrder = stopOrder
        self.totalDuration = totalDuration
        self.totalDistance = totalDistance
        self.costSource = costSource
        self.approximationReason = approximationReason
        self.isUpToDate = true
    }
}
