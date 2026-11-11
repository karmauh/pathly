import Foundation
import SwiftData
import Testing
@testable import pathly

@MainActor
@Suite("SwiftDataParcelStore")
struct SwiftDataParcelStoreTests {
    let container: ModelContainer
    let store: SwiftDataParcelStore
    let address = Address(street: "ul. Długa", buildingNumber: "12", postalCode: "31-019", city: "Kraków")
    let krakow = Coordinate(latitude: 50.06, longitude: 19.94)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        store = SwiftDataParcelStore(context: container.mainContext)
    }

    private func parcel(_ id: UUID) throws -> Parcel? {
        try container.mainContext.fetch(FetchDescriptor<Parcel>(predicate: #Predicate { $0.id == id })).first
    }

    @Test("Nowa przesyłka czeka na geokodowanie")
    func addParcel() throws {
        let id = try store.addParcel(address: address)
        let saved = try #require(try parcel(id))
        #expect(saved.address == address)
        #expect(saved.geocodingStatus == .pending)
        #expect(saved.deliveryStatus == .pending)
    }

    @Test("Zmiana adresu wraca do kolejki, powrót do poprzedniego nie wymaga zapytania")
    func updateResetsGeocoding() throws {
        let id = try store.addParcel(address: address)
        let saved = try #require(try parcel(id))
        try store.recordGeocoding(.located(krakow), ofParcel: id, for: address)

        var changed = address
        changed.buildingNumber = "14"
        try store.updateAddress(ofParcel: id, to: changed)
        #expect(saved.address == changed)
        #expect(saved.geocodingStatus == .pending)

        try store.updateAddress(ofParcel: id, to: address)
        #expect(saved.geocodingStatus == .succeeded)
        #expect(saved.coordinate == krakow)
    }

    @Test("Zapis wyniku geokodowania")
    func recordOutcomes() throws {
        let id = try store.addParcel(address: address)
        let saved = try #require(try parcel(id))

        let candidates = [GeocodingCandidate(coordinate: krakow, label: "A"), GeocodingCandidate(coordinate: Coordinate(latitude: 50.3, longitude: 19.5), label: "B")]
        #expect(try store.recordGeocoding(.ambiguous(candidates), ofParcel: id, for: address))
        #expect(saved.geocodingStatus == .ambiguous)
        #expect(try store.geocodingCandidates(ofParcel: id) == candidates)

        try store.chooseLocation(candidates[1], forParcel: id)
        #expect(saved.geocodingStatus == .succeeded)
        #expect(saved.coordinate == candidates[1].coordinate)
        #expect(saved.geocodedAddress == address)
        #expect(try store.geocodingCandidates(ofParcel: id).isEmpty)

        #expect(try store.recordGeocoding(.notFound, ofParcel: id, for: address))
        #expect(saved.geocodingStatus == .notFound)
    }

    @Test("Wynik dla nieaktualnego adresu jest odrzucany")
    func recordStaleOutcome() throws {
        let id = try store.addParcel(address: address)
        var old = address
        old.buildingNumber = "1"
        #expect(try !store.recordGeocoding(.located(krakow), ofParcel: id, for: old))
        #expect(try parcel(id)?.geocodingStatus == .pending)
        #expect(try !store.recordGeocoding(.located(krakow), ofParcel: UUID(), for: address))
    }

    @Test("Znane współrzędne i wyszukiwanie po statusie")
    func knownCoordinateAndStatus() throws {
        let first = try store.addParcel(address: address)
        let second = try store.addParcel(address: address)
        #expect(try store.knownCoordinate(for: address) == nil)

        try store.recordGeocoding(.located(krakow), ofParcel: first, for: address)
        #expect(try store.knownCoordinate(for: address) == krakow)
        #expect(try store.parcelIDs(withStatus: .pending) == [second])
        #expect(try store.parcelIDs(withStatus: .succeeded) == [first])
    }

    @Test("Zapis tego samego adresu nie rusza geokodowania")
    func updateWithSameAddress() throws {
        let id = try store.addParcel(address: address)
        let saved = try #require(try parcel(id))
        saved.geocodingStatus = .succeeded
        saved.geocodedAddress = address

        try store.updateAddress(ofParcel: id, to: address)
        #expect(saved.geocodingStatus == .succeeded)
    }

    @Test("Usuwanie wybranych przesyłek")
    func delete() throws {
        let first = try store.addParcel(address: address)
        let second = try store.addParcel(address: address)
        try store.deleteParcels([first])
        #expect(try parcel(first) == nil)
        #expect(try parcel(second) != nil)
    }

    @Test("Aktualizacja nieistniejącej przesyłki zgłasza błąd")
    func updateMissing() {
        #expect(throws: ParcelStoreError.self) {
            try store.updateAddress(ofParcel: UUID(), to: address)
        }
    }
}
