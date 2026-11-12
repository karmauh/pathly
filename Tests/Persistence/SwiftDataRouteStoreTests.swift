import Foundation
import SwiftData
import Testing
@testable import pathly

@MainActor
@Suite("SwiftDataRouteStore i unieważnianie trasy")
struct SwiftDataRouteStoreTests {
    let container: ModelContainer
    let routes: SwiftDataRouteStore
    let parcels: SwiftDataParcelStore
    let address = Address(street: "ul. Długa", buildingNumber: "12", postalCode: "31-019", city: "Kraków")
    let krakow = Coordinate(latitude: 50.06, longitude: 19.94)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        routes = SwiftDataRouteStore(context: container.mainContext)
        parcels = SwiftDataParcelStore(context: container.mainContext)
    }

    private func savedRoutes() throws -> [Route] {
        try container.mainContext.fetch(FetchDescriptor<Route>())
    }

    private func planned(_ order: [UUID], source: CostSource = .roadNetwork, reason: ApproximationReason? = nil) -> PlannedRoute {
        PlannedRoute(stopOrder: order, totalDuration: 600, totalDistance: 5000, costSource: source, approximationReason: reason, stoppedByTimeLimit: false)
    }

    /// Przesyłka z ustalonym położeniem i aktualna trasa, która ją obejmuje.
    private func locatedParcelWithRoute() throws -> UUID {
        let id = try parcels.addParcel(address: address)
        try parcels.recordGeocoding(.located(krakow), ofParcel: id, for: address)
        try routes.saveRoute(planned([id]))
        return id
    }

    @Test("Nowa trasa zastępuje poprzednią i zachowuje powód przybliżenia")
    func savesSingleRoute() throws {
        let first = UUID()
        let second = UUID()
        try routes.saveRoute(planned([first]))
        try routes.saveRoute(planned([second, first], source: .approximate, reason: .offline))

        let saved = try savedRoutes()
        #expect(saved.count == 1)
        #expect(saved.first?.stopOrder == [second, first])
        #expect(saved.first?.costSource == .approximate)
        #expect(saved.first?.approximationReason == .offline)
        #expect(saved.first?.isUpToDate == true)
    }

    @Test("Dodanie przesyłki unieważnia trasę")
    func addInvalidates() throws {
        _ = try locatedParcelWithRoute()
        _ = try parcels.addParcel(address: address)
        #expect(try savedRoutes().first?.isUpToDate == false)
    }

    @Test("Usunięcie przesyłki unieważnia trasę")
    func deleteInvalidates() throws {
        let id = try locatedParcelWithRoute()
        try parcels.deleteParcels([id])
        #expect(try savedRoutes().first?.isUpToDate == false)
    }

    @Test("Zmiana adresu unieważnia trasę, zapis bez zmian — nie")
    func addressChangeInvalidates() throws {
        let id = try locatedParcelWithRoute()
        try parcels.updateAddress(ofParcel: id, to: address)
        #expect(try savedRoutes().first?.isUpToDate == true)

        var changed = address
        changed.buildingNumber = "14"
        try parcels.updateAddress(ofParcel: id, to: changed)
        #expect(try savedRoutes().first?.isUpToDate == false)
    }

    @Test("Nowe położenie przesyłki unieważnia trasę, to samo położenie — nie")
    func geocodingInvalidates() throws {
        let id = try locatedParcelWithRoute()
        try parcels.recordGeocoding(.located(krakow), ofParcel: id, for: address)
        #expect(try savedRoutes().first?.isUpToDate == true)

        try parcels.recordGeocoding(.located(Coordinate(latitude: 50.07, longitude: 19.95)), ofParcel: id, for: address)
        #expect(try savedRoutes().first?.isUpToDate == false)
    }

    @Test("Wybór miejsca z kandydatów unieważnia trasę")
    func chooseLocationInvalidates() throws {
        let id = try locatedParcelWithRoute()
        try parcels.chooseLocation(GeocodingCandidate(coordinate: krakow, label: "Długa 12, Kraków", city: "Kraków", postalCode: "31-019"), forParcel: id)
        #expect(try savedRoutes().first?.isUpToDate == false)
    }

    @Test("Położenie wskazane na mapie zapisuje się jako ustalone i unieważnia trasę")
    func manualLocation() throws {
        let id = try locatedParcelWithRoute()
        let pin = Coordinate(latitude: 50.1, longitude: 19.9)
        try parcels.setManualLocation(pin, forParcel: id)

        let parcel = try #require(try container.mainContext.fetch(FetchDescriptor<Parcel>()).first)
        #expect(parcel.coordinate == pin)
        #expect(parcel.geocodingStatus == .succeeded)
        #expect(parcel.geocodedAddress == parcel.address)
        #expect(try savedRoutes().first?.isUpToDate == false)
        #expect(try parcels.knownCoordinate(for: address) == pin, "Inna paczka pod ten adres przejmie pinezkę")
    }

    @Test("Status doręczenia nie unieważnia trasy")
    func deliveryKeepsRoute() throws {
        let id = try locatedParcelWithRoute()
        try parcels.setDeliveryStatus(.delivered, ofParcel: id)

        #expect(try savedRoutes().first?.isUpToDate == true)
        let parcel = try container.mainContext.fetch(FetchDescriptor<Parcel>()).first
        #expect(parcel?.deliveryStatus == .delivered)
        #expect(throws: ParcelStoreError.self) { try parcels.setDeliveryStatus(.delivered, ofParcel: UUID()) }
    }

    @Test("Kandydaci do trasy: tylko niedoręczone, z podziałem na gotowe i blokujące")
    func routeCandidates() throws {
        let ready = try parcels.addParcel(address: address)
        try parcels.recordGeocoding(.located(krakow), ofParcel: ready, for: address)
        let delivered = try parcels.addParcel(address: address)
        try parcels.recordGeocoding(.located(krakow), ofParcel: delivered, for: address)
        try parcels.setDeliveryStatus(.delivered, ofParcel: delivered)
        let notDelivered = try parcels.addParcel(address: address)
        try parcels.recordGeocoding(.located(krakow), ofParcel: notDelivered, for: address)
        try parcels.setDeliveryStatus(.notDelivered, ofParcel: notDelivered)
        let notFound = try parcels.addParcel(address: address)
        try parcels.recordGeocoding(.notFound, ofParcel: notFound, for: address)
        let failed = try parcels.addParcel(address: address)
        try parcels.recordGeocoding(.failed, ofParcel: failed, for: address)
        _ = try parcels.addParcel(address: address)  // czeka na geokodowanie

        let candidates = try parcels.routeCandidates()

        #expect(candidates.stops == [RouteStop(parcelID: ready, coordinate: krakow)])
        #expect(candidates.needingAttention == 2)
        #expect(candidates.awaitingGeocoding == 1)
    }

    @Test("Koniec dnia: doręczone i trasa znikają, niedoręczone wracają do doręczenia")
    func finishDay() throws {
        let delivered = try locatedParcelWithRoute()
        try parcels.setDeliveryStatus(.delivered, ofParcel: delivered)
        let notDelivered = try parcels.addParcel(address: address)
        try parcels.setDeliveryStatus(.notDelivered, ofParcel: notDelivered)
        let untouched = try parcels.addParcel(address: address)

        let summary = try parcels.finishDay()

        #expect(summary == DaySummary(removed: 1, carriedOver: 1))
        #expect(try savedRoutes().isEmpty)
        let remaining = try container.mainContext.fetch(FetchDescriptor<Parcel>())
        #expect(Set(remaining.map(\.id)) == [notDelivered, untouched])
        #expect(remaining.allSatisfy { $0.deliveryStatus == .pending })
    }
}
