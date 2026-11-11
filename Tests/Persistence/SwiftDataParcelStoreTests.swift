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

    @Test("Zmiana adresu unieważnia współrzędne")
    func updateResetsGeocoding() throws {
        let id = try store.addParcel(address: address)
        let saved = try #require(try parcel(id))
        saved.coordinate = Coordinate(latitude: 50.06, longitude: 19.94)
        saved.geocodedAddress = address
        saved.geocodingStatus = .succeeded

        var changed = address
        changed.buildingNumber = "14"
        try store.updateAddress(ofParcel: id, to: changed)

        #expect(saved.address == changed)
        #expect(saved.coordinate == nil)
        #expect(saved.geocodingStatus == .pending)
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
