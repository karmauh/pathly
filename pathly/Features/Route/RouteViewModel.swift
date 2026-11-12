import Foundation
import Observation

/// Akcje ekranu trasy: wyliczenie w tle z postępem i oznaczanie doręczeń.
/// Samą trasę i przesyłki widok czyta przez `@Query`.
@Observable
final class RouteViewModel {
    enum Activity: Equatable {
        case idle
        case computing(RoutePlanningPhase)
    }

    private(set) var activity: Activity = .idle
    private(set) var errorMessage: String?

    private let planner: RoutePlanner
    private let baseStore: any BaseStore
    private let deliveries: any DeliveryStore
    private let routes: any RouteStore
    private var task: Task<Void, Never>?

    init(planner: RoutePlanner, baseStore: any BaseStore, deliveries: any DeliveryStore, routes: any RouteStore) {
        self.planner = planner
        self.baseStore = baseStore
        self.deliveries = deliveries
        self.routes = routes
    }

    var isComputing: Bool { activity != .idle }

    /// Uruchamia wyliczenie w tle. Interfejs pozostaje responsywny.
    func startComputing() {
        guard task == nil else { return }
        task = Task {
            await computeRoute()
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Pobiera macierz, optymalizuje i zapisuje trasę.
    func computeRoute() async {
        errorMessage = nil
        defer { activity = .idle }
        do {
            let base = try baseStore.loadBase()?.coordinate
            let candidates = try deliveries.routeCandidates()
            try planner.validate(base: base, candidates: candidates)

            activity = .computing(.fetchingMatrix(completedRequests: 0, totalRequests: 0))
            let route = try await planner.plan(base: base, candidates: candidates) { [weak self] phase in
                Task { @MainActor in self?.advance(to: phase) }
            }
            try routes.saveRoute(route)
        } catch is CancellationError {
            // Kurier przerwał — poprzednia trasa zostaje bez zmian.
        } catch let error as RoutePlanningError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Nie udało się wyliczyć trasy. Spróbuj ponownie."
        }
    }

    func setStatus(_ status: DeliveryStatus, ofParcel id: UUID) {
        do {
            try deliveries.setDeliveryStatus(status, ofParcel: id)
        } catch {
            errorMessage = "Nie udało się zapisać statusu przesyłki."
        }
    }

    /// Komunikat po zakończeniu dnia, np. „Usunięto 98 doręczonych przesyłek.”
    private(set) var daySummaryMessage: String?

    func finishDay() {
        do {
            let summary = try deliveries.finishDay()
            var parts = ["Usunięto doręczone przesyłki: \(summary.removed)."]
            if summary.carriedOver > 0 {
                parts.append("Niedoręczone (\(summary.carriedOver)) zostają na liście na kolejny dzień.")
            }
            daySummaryMessage = parts.joined(separator: " ")
        } catch {
            errorMessage = "Nie udało się zakończyć dnia. Spróbuj ponownie."
        }
    }

    func dismissDaySummary() {
        daySummaryMessage = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Powiadomienia o postępie przychodzą z tła i mogą się spóźnić — etap
    /// nigdy się nie cofa, a po zakończeniu są ignorowane.
    private func advance(to phase: RoutePlanningPhase) {
        guard case .computing(let current) = activity, phase.rank >= current.rank else { return }
        activity = .computing(phase)
    }
}
