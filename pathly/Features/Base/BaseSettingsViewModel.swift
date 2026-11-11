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

    /// Formularz adresu — widok wiąże się z nim bezpośrednio.
    var form = AddressForm()

    private(set) var savedBase: BaseLocation?
    private(set) var status: Status = .idle

    private let store: any BaseStore
    private let geocoder: any Geocoder

    init(store: any BaseStore, geocoder: any Geocoder) {
        self.store = store
        self.geocoder = geocoder
    }

    var canSave: Bool {
        form.validationErrors.isEmpty && status != .saving
    }

    /// Wczytuje zapisaną bazę i wypełnia nią formularz.
    func load() {
        do {
            savedBase = try store.loadBase()
            if let savedBase {
                form = AddressForm(address: savedBase.address)
            }
        } catch {
            status = .failed("Nie udało się wczytać zapisanej bazy.")
        }
    }

    /// Geokoduje adres z formularza i zapisuje go jako bazę.
    func save() async {
        let address = form.address
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
                form = AddressForm(address: address)
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
}
