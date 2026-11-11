import Foundation
import Testing
@testable import pathly

@MainActor
@Suite("ParcelListViewModel")
struct ParcelListViewModelTests {
    let address = Address(street: "Polna", buildingNumber: "2", postalCode: "90-001", city: "Łódź")

    @Test("Usuwa wskazane przesyłki")
    func delete() throws {
        let store = InMemoryParcelStore()
        let keep = try store.addParcel(address: address)
        let remove = try store.addParcel(address: address)
        let viewModel = ParcelListViewModel(store: store)

        viewModel.delete([remove])

        #expect(Set(store.parcels.keys) == [keep])
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Błąd usuwania pokazuje komunikat")
    func deleteFailure() {
        let store = InMemoryParcelStore()
        store.shouldFail = true
        let viewModel = ParcelListViewModel(store: store)

        viewModel.delete([UUID()])
        #expect(viewModel.errorMessage != nil)

        viewModel.dismissError()
        #expect(viewModel.errorMessage == nil)
    }
}
