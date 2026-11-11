import Foundation
import SwiftData

/// Wyliczona trasa (model SwiftData). Wypełniana od etapu 6.
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
    /// `false`, gdy po wyliczeniu dodano lub usunięto przesyłkę.
    var isUpToDate: Bool

    init(
        createdAt: Date = .now,
        stopOrder: [UUID],
        totalDuration: TimeInterval,
        totalDistance: Double,
        costSource: CostSource
    ) {
        self.createdAt = createdAt
        self.stopOrder = stopOrder
        self.totalDuration = totalDuration
        self.totalDistance = totalDistance
        self.costSource = costSource
        self.isUpToDate = true
    }
}
