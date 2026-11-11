import Foundation
import Testing
@testable import pathly

/// Atrapa geokodera: zwraca zadany wynik i zlicza wywołania.
@MainActor
final class MockGeocoder: Geocoder {
    var result: Result<GeocodingResult, Error>
    private(set) var requestedAddresses: [Address] = []

    init(result: Result<GeocodingResult, Error>) {
        self.result = result
    }

    func geocode(_ address: Address) async throws -> GeocodingResult {
        requestedAddresses.append(address)
        return try result.get()
    }
}

/// Magazyn w pamięci — test view modelu nie zależy od SwiftData.
@MainActor
final class InMemoryBaseStore: BaseStore {
    var base: BaseLocation?
    func loadBase() throws -> BaseLocation? { base }
    func saveBase(_ base: BaseLocation) throws { self.base = base }
}

@MainActor
@Suite("BaseSettingsViewModel")
struct BaseSettingsViewModelTests {
    let found = Coordinate(latitude: 52.18, longitude: 21.0)

    private func makeViewModel(
        result: Result<GeocodingResult, Error>,
        stored: BaseLocation? = nil
    ) -> (BaseSettingsViewModel, MockGeocoder, InMemoryBaseStore) {
        let geocoder = MockGeocoder(result: result)
        let store = InMemoryBaseStore()
        store.base = stored
        return (BaseSettingsViewModel(store: store, geocoder: geocoder), geocoder, store)
    }

    private func fillValidForm(_ viewModel: BaseSettingsViewModel) {
        viewModel.form.street = " ul. Magazynowa "
        viewModel.form.buildingNumber = "5"
        viewModel.form.postalCode = "02-652"
        viewModel.form.city = "Warszawa"
    }

    @Test("Udane geokodowanie zapisuje znormalizowaną bazę")
    func successfulSave() async {
        let (viewModel, geocoder, store) = makeViewModel(
            result: .success(.found(GeocodingCandidate(coordinate: found, label: "")))
        )
        fillValidForm(viewModel)

        await viewModel.save()

        #expect(viewModel.status == .saved)
        #expect(store.base == BaseLocation(address: .init(street: "ul. Magazynowa", buildingNumber: "5", postalCode: "02-652", city: "Warszawa"), coordinate: found))
        #expect(viewModel.savedBase == store.base)
        #expect(geocoder.requestedAddresses.count == 1)
    }

    @Test("Nieznaleziony adres nie zapisuje bazy")
    func notFound() async {
        let (viewModel, _, store) = makeViewModel(result: .success(.notFound))
        fillValidForm(viewModel)

        await viewModel.save()

        #expect(store.base == nil)
        guard case .failed = viewModel.status else {
            Issue.record("Oczekiwano błędu, otrzymano \(viewModel.status)")
            return
        }
    }

    @Test("Niejednoznaczny adres nie zapisuje bazy")
    func ambiguous() async {
        let (viewModel, _, store) = makeViewModel(result: .success(.ambiguous([])))
        fillValidForm(viewModel)

        await viewModel.save()

        #expect(store.base == nil)
        #expect(viewModel.status != .saved)
    }

    @Test("Błąd geokodera pokazuje jego komunikat")
    func geocoderError() async {
        let (viewModel, _, _) = makeViewModel(result: .failure(GeocodingError.rateLimited))
        fillValidForm(viewModel)

        await viewModel.save()

        #expect(viewModel.status == .failed(GeocodingError.rateLimited.localizedDescription))
    }

    @Test("Niepoprawny formularz nie wywołuje geokodera")
    func invalidFormSkipsGeocoding() async {
        let (viewModel, geocoder, _) = makeViewModel(result: .success(.notFound))
        viewModel.form.city = "Warszawa"

        #expect(!viewModel.canSave)
        await viewModel.save()

        #expect(geocoder.requestedAddresses.isEmpty)
        #expect(viewModel.status == .failed(Address.ValidationError.missingBuildingNumber.message))
    }

    @Test("Wczytanie wypełnia formularz, a niezmieniony adres nie jest geokodowany ponownie")
    func loadAndSkipUnchanged() async {
        let (viewModel, geocoder, _) = makeViewModel(result: .success(.notFound), stored: .sample)

        viewModel.load()
        #expect(viewModel.form.street == "ul. Magazynowa")
        #expect(viewModel.form.postalCode == "02-652")

        await viewModel.save()
        #expect(geocoder.requestedAddresses.isEmpty)
        #expect(viewModel.status == .saved)
    }
}
