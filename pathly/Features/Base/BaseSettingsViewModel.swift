import Foundation
import Observation

/// Logika ekranu ustawień bazy: walidacja formularza, geokodowanie i zapis.
@Observable
final class BaseSettingsViewModel {
    enum Status: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    // Pola formularza — widok wiąże się z nimi bezpośrednio.
    var street = ""
    var buildingNumber = ""
    var apartmentNumber = ""
    var postalCode = ""
    var city = ""

    private(set) var savedBase: BaseLocation?
    private(set) var status: Status = .idle

    private let store: any BaseStore
    private let geocoder: any Geocoder

    init(store: any BaseStore, geocoder: any Geocoder) {
        self.store = store
        self.geocoder = geocoder
    }

    /// Adres z formularza po normalizacji.
    var formAddress: Address {
        Address(
            street: street,
            buildingNumber: buildingNumber,
            apartmentNumber: apartmentNumber,
            postalCode: postalCode,
            city: city
        ).normalized()
    }

    var validationErrors: [Address.ValidationError] {
        formAddress.validationErrors
    }

    var canSave: Bool {
        validationErrors.isEmpty && status != .saving
    }

    /// Wczytuje zapisaną bazę i wypełnia nią formularz.
    func load() {
        do {
            savedBase = try store.loadBase()
            if let savedBase {
                fillForm(with: savedBase.address)
            }
        } catch {
            status = .failed("Nie udało się wczytać zapisanej bazy.")
        }
    }

    /// Geokoduje adres z formularza i zapisuje go jako bazę.
    func save() async {
        let address = formAddress
        if let firstError = address.validationErrors.first {
            status = .failed(firstError.message)
            return
        }
        // Niezmieniony adres nie jest geokodowany ponownie (oszczędzamy limit Apple).
        if savedBase?.address == address {
            status = .saved
            return
        }

        status = .saving
        do {
            switch try await geocoder.geocode(address) {
            case .found(let candidate):
                let base = BaseLocation(address: address, coordinate: candidate.coordinate)
                try store.saveBase(base)
                savedBase = base
                fillForm(with: address)
                status = .saved
            case .notFound:
                status = .failed("Nie znaleziono tego adresu. Sprawdź pola i spróbuj ponownie.")
            case .ambiguous:
                status = .failed("Adres pasuje do kilku miejsc. Doprecyzuj ulicę lub kod pocztowy.")
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func fillForm(with address: Address) {
        street = address.street
        buildingNumber = address.buildingNumber
        apartmentNumber = address.apartmentNumber ?? ""
        postalCode = address.postalCode
        city = address.city
    }
}
