import Foundation
import SwiftData

/// Zapis bieżącej trasy.
///
/// Widok trasy czyta dane przez `@Query`; zapis przechodzi przez ten protokół.
protocol RouteStore {
    /// Zastępuje poprzednią trasę nową.
    func saveRoute(_ route: PlannedRoute) throws
}

/// Operacje na przesyłkach potrzebne przy wyliczaniu i realizacji trasy.
protocol DeliveryStore {
    /// Przesyłki czekające na doręczenie: gotowe do trasy oraz te, które ją blokują.
    func routeCandidates() throws -> RouteCandidates
    /// Status doręczenia nie zmienia kolejności, więc nie unieważnia trasy.
    func setDeliveryStatus(_ status: DeliveryStatus, ofParcel id: UUID) throws
    /// Koniec dnia: usuwa doręczone przesyłki i trasę, niedoręczone wracają do
    /// doręczenia następnego dnia. Przesyłki jeszcze nieobsłużone zostają bez zmian.
    @discardableResult
    func finishDay() throws -> DaySummary
}

/// Wynik zakończenia dnia.
nonisolated struct DaySummary: Hashable, Sendable {
    /// Usunięte, bo doręczone.
    var removed: Int
    /// Niedoręczone — zostają na liście do ponownego doręczenia.
    var carriedOver: Int
}

/// Implementacja `RouteStore` na SwiftData.
final class SwiftDataRouteStore: RouteStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func saveRoute(_ route: PlannedRoute) throws {
        try context.delete(model: Route.self)
        context.insert(Route(
            stopOrder: route.stopOrder,
            totalDuration: route.totalDuration,
            totalDistance: route.totalDistance,
            costSource: route.costSource,
            approximationReason: route.approximationReason
        ))
        try context.save()
    }
}

extension ModelContext {
    /// Oznacza bieżącą trasę jako nieaktualną — po dodaniu, usunięciu albo
    /// przeniesieniu przesyłki kolejność trzeba wyliczyć ponownie.
    func invalidateRoute() throws {
        for route in try fetch(FetchDescriptor<Route>()) where route.isUpToDate {
            route.isUpToDate = false
        }
    }
}
