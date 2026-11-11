import SwiftData
import Testing
@testable import pathly

@MainActor
@Suite("SwiftDataBaseStore")
struct SwiftDataBaseStoreTests {
    let container: ModelContainer
    let store: SwiftDataBaseStore

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        store = SwiftDataBaseStore(context: container.mainContext)
    }

    @Test("Pusta baza danych nie zwraca bazy")
    func emptyStore() throws {
        #expect(try store.loadBase() == nil)
    }

    @Test("Zapis i odczyt bazy")
    func saveAndLoad() throws {
        try store.saveBase(.sample)
        #expect(try store.loadBase() == .sample)
    }

    @Test("Ponowny zapis nadpisuje bazę zamiast dodawać drugą")
    func overwrite() throws {
        try store.saveBase(.sample)
        var moved = BaseLocation.sample
        moved.address.buildingNumber = "99"
        moved.coordinate = Coordinate(latitude: 50.0647, longitude: 19.9450)
        try store.saveBase(moved)

        #expect(try store.loadBase() == moved)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Base>()) == 1)
    }
}

extension BaseLocation {
    static let sample = BaseLocation(
        address: Address(street: "ul. Magazynowa", buildingNumber: "5", postalCode: "02-652", city: "Warszawa"),
        coordinate: Coordinate(latitude: 52.18, longitude: 21.0)
    )
}
