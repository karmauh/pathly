import Foundation
import SwiftData
import Testing
@testable import pathly

@MainActor
@Suite("RouteViewModel i RouteProgress")
struct RouteViewModelTests {
    let container: ModelContainer
    let parcels: SwiftDataParcelStore
    let bases: SwiftDataBaseStore
    let viewModel: RouteViewModel
    let address = Address(street: "ul. Długa", buildingNumber: "12", postalCode: "31-019", city: "Kraków")

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        parcels = SwiftDataParcelStore(context: container.mainContext)
        bases = SwiftDataBaseStore(context: container.mainContext)
        viewModel = RouteViewModel(
            planner: RoutePlanner(costProvider: HaversineCostProvider(reason: .missingAPIKey)),
            baseStore: bases,
            deliveries: parcels,
            routes: SwiftDataRouteStore(context: container.mainContext)
        )
    }

    private func savedRoute() throws -> Route? {
        try container.mainContext.fetch(FetchDescriptor<Route>()).first
    }

    @discardableResult
    private func addLocatedParcels(_ count: Int) throws -> [UUID] {
        try (0..<count).map { index in
            let id = try parcels.addParcel(address: address)
            try parcels.recordGeocoding(.located(Coordinate(latitude: 50.06 + Double(index) * 0.01, longitude: 19.94)), ofParcel: id, for: address)
            return id
        }
    }

    private func saveBase() throws {
        try bases.saveBase(BaseLocation(address: address, coordinate: Coordinate(latitude: 50.05, longitude: 19.94)))
    }

    @Test("Wylicza i zapisuje trasę ze wszystkimi przesyłkami, potem wraca do stanu spoczynku")
    func computesRoute() async throws {
        try saveBase()
        let ids = try addLocatedParcels(5)

        await viewModel.computeRoute()

        let route = try #require(try savedRoute())
        #expect(Set(route.stopOrder) == Set(ids))
        #expect(route.isUpToDate)
        #expect(route.costSource == .approximate)
        #expect(route.approximationReason == .missingAPIKey)
        #expect(viewModel.activity == .idle)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Bez bazy — komunikat i brak trasy")
    func missingBase() async throws {
        try addLocatedParcels(2)

        await viewModel.computeRoute()

        #expect(viewModel.errorMessage == RoutePlanningError.missingBase.errorDescription)
        #expect(try savedRoute() == nil)
        viewModel.dismissError()
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Przesyłka bez położenia blokuje wyliczenie")
    func parcelNeedsAttention() async throws {
        try saveBase()
        try addLocatedParcels(2)
        let broken = try parcels.addParcel(address: address)
        try parcels.recordGeocoding(.notFound, ofParcel: broken, for: address)

        await viewModel.computeRoute()

        #expect(viewModel.errorMessage == RoutePlanningError.parcelsNeedAttention(count: 1).errorDescription)
    }

    @Test("Przeliczenie po doręczeniach obejmuje tylko niezrealizowane przesyłki")
    func recomputeSkipsCompleted() async throws {
        try saveBase()
        let ids = try addLocatedParcels(4)
        viewModel.setStatus(.delivered, ofParcel: ids[0])
        viewModel.setStatus(.notDelivered, ofParcel: ids[1])

        await viewModel.computeRoute()

        #expect(Set(try #require(try savedRoute()).stopOrder) == Set(ids[2...]))
    }

    @Test("Błąd zapisu statusu — komunikat")
    func statusError() {
        viewModel.setStatus(.delivered, ofParcel: UUID())
        #expect(viewModel.errorMessage != nil)
    }

    @Test("Bieżący przystanek to pierwszy niezrealizowany; usunięte przesyłki są pomijane")
    func routeProgress() {
        let ids = (0..<4).map { _ in UUID() }
        var statuses: [UUID: DeliveryStatus] = [ids[0]: .delivered, ids[1]: .notDelivered, ids[2]: .pending, ids[3]: .pending]

        let progress = RouteProgress(stopOrder: ids, statuses: statuses)
        #expect(progress.current?.parcelID == ids[2])
        #expect(progress.current?.number == 3)
        #expect(progress.deliveredCount == 1 && progress.notDeliveredCount == 1 && progress.completedCount == 2)
        #expect(!progress.isFinished)

        statuses[ids[1]] = nil  // przesyłka usunięta
        statuses[ids[2]] = .delivered
        statuses[ids[3]] = .delivered
        let finished = RouteProgress(stopOrder: ids, statuses: statuses)
        #expect(finished.entries.map(\.number) == [1, 2, 3])
        #expect(finished.entries.map(\.parcelID) == [ids[0], ids[2], ids[3]])
        #expect(finished.current == nil)
        #expect(finished.isFinished)
        #expect(!RouteProgress(stopOrder: [], statuses: [:]).isFinished)
    }
}
