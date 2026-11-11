import CoreGraphics
import Foundation
import Observation

/// Logika ekranu podglądu adresu: OCR zdjęcia, wypełnienie formularza wynikiem
/// parsera, wybór kandydata i zatwierdzenie przesyłki.
///
/// Nic nie trafia do bazy bez wywołania `approve()` przez kuriera. Zatwierdzona
/// przesyłka od razu trafia do kolejki geokodowania.
@Observable
final class AddressReviewViewModel {
    enum Mode: Equatable {
        /// Nowa przesyłka ze zdjęcia etykiety.
        case photo
        /// Nowa przesyłka wpisana ręcznie.
        case manual
        /// Poprawa adresu istniejącej przesyłki.
        case edit(UUID)
    }

    enum Phase: Equatable {
        case recognizing
        /// Parser znalazł kilka adresów bez kotwic — kurier wybiera właściwy.
        case choosingCandidate
        case reviewing
    }

    /// Próg, poniżej którego prosimy kuriera o szczególną uwagę.
    static let lowConfidenceThreshold = 0.6

    let mode: Mode
    var form = AddressForm()
    private(set) var phase: Phase
    private(set) var candidates: [ParsedAddress] = []
    /// Pola, które parser poprawiał lub których nie znalazł.
    private(set) var parserFlaggedFields: Set<AddressForm.Field> = []
    /// Po pierwszej próbie zatwierdzenia wyróżniamy też pola z błędami walidacji.
    private var didAttemptApproval = false
    /// Komunikat nad formularzem (np. „Nie rozpoznano adresu”).
    private(set) var notice: String?
    private(set) var errorMessage: String?
    /// Miejsca do wyboru, gdy geokodowanie edytowanej przesyłki dało kilka wyników.
    private(set) var locationCandidates: [GeocodingCandidate] = []
    /// Adres wczytany do edycji — kandydaci i problem z geokodowaniem dotyczą tylko jego.
    private var loadedAddress: Address?
    private var geocodingNotice: String?

    private let recognizer: any TextRecognizer
    private let parser: AddressParser
    private let store: any ParcelStore
    private let geocoding: any GeocodingScheduling

    init(
        mode: Mode,
        recognizer: any TextRecognizer,
        parser: AddressParser = AddressParser(),
        store: any ParcelStore,
        geocoding: any GeocodingScheduling
    ) {
        self.mode = mode
        self.recognizer = recognizer
        self.parser = parser
        self.store = store
        self.geocoding = geocoding
        self.phase = mode == .photo ? .recognizing : .reviewing
    }

    var title: String {
        switch mode {
        case .photo, .manual: "Nowa przesyłka"
        case .edit: "Popraw adres"
        }
    }

    var canApprove: Bool {
        phase == .reviewing && form.validationErrors.isEmpty
    }

    /// Pola do wyróżnienia w formularzu.
    var fieldsToCheck: Set<AddressForm.Field> {
        didAttemptApproval ? parserFlaggedFields.union(form.invalidFields) : parserFlaggedFields
    }

    /// Czy pokazać wybór miejsca. Po zmianie adresu w formularzu kandydaci
    /// przestają pasować — adres zostanie geokodowany od nowa.
    var canChooseLocation: Bool {
        !locationCandidates.isEmpty && form.address == loadedAddress
    }

    /// Dlaczego nie udało się ustalić położenia edytowanej przesyłki. Znika,
    /// gdy kurier zmieni adres — nowy zostanie sprawdzony po zatwierdzeniu.
    var geocodingProblem: String? {
        form.address == loadedAddress ? geocodingNotice : nil
    }

    /// Wczytuje adres edytowanej przesyłki.
    func load() {
        guard case .edit(let id) = mode else { return }
        do {
            if let address = try store.address(ofParcel: id) {
                form = AddressForm(address: address)
                loadedAddress = form.address
            }
            locationCandidates = try store.geocodingCandidates(ofParcel: id)
            geocodingNotice = Self.notice(for: try store.geocodingStatus(ofParcel: id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rozpoznaje tekst na zdjęciu i wypełnia formularz wynikiem parsera.
    func recognize(_ image: CGImage) async {
        phase = .recognizing
        do {
            let lines = try await recognizer.recognizeLines(in: image)
            apply(parser.parse(lines))
        } catch {
            notice = "Nie udało się odczytać tekstu ze zdjęcia. Wpisz adres ręcznie."
            phase = .reviewing
        }
    }

    /// Kurier wybrał jednego z kandydatów.
    func choose(_ candidate: ParsedAddress) {
        fill(with: candidate)
        notice = "Sprawdź, czy wybrany adres to adres odbiorcy."
        phase = .reviewing
    }

    /// Kurier woli wpisać adres sam zamiast wybierać z listy.
    func enterManually() {
        form = AddressForm()
        parserFlaggedFields = []
        notice = nil
        phase = .reviewing
    }

    /// Zapisuje przesyłkę. Zwraca `true`, gdy się udało.
    @discardableResult
    func approve() -> Bool {
        didAttemptApproval = true
        if let firstError = form.validationErrors.first {
            errorMessage = firstError.message
            return false
        }
        do {
            let id: UUID
            switch mode {
            case .photo, .manual:
                id = try store.addParcel(address: form.address)
            case .edit(let editedID):
                id = editedID
                try store.updateAddress(ofParcel: id, to: form.address)
            }
            // Kolejka sama pominie adres, dla którego zna już współrzędne.
            geocoding.enqueue(id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Kurier wskazał właściwe miejsce dla niejednoznacznego adresu.
    @discardableResult
    func chooseLocation(_ candidate: GeocodingCandidate) -> Bool {
        guard case .edit(let id) = mode else { return false }
        do {
            try store.chooseLocation(candidate, forParcel: id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func notice(for status: GeocodingStatus?) -> String? {
        switch status {
        case .notFound: "Nie znaleziono tego adresu na mapie. Sprawdź ulicę, numer i miejscowość."
        case .failed: "Nie udało się ustalić położenia z powodu błędu połączenia. Zatwierdź, aby spróbować ponownie."
        case .ambiguous, .pending, .succeeded, nil: nil
        }
    }

    private func apply(_ result: AddressParsingResult) {
        switch result {
        case .recipient(let parsed):
            fill(with: parsed)
            if parsed.warnings.contains(.recipientNotMarked) {
                notice = "Na etykiecie nie oznaczono odbiorcy. Sprawdź, czy to właściwy adres."
            } else if parsed.confidence < Self.lowConfidenceThreshold {
                notice = "Odczyt jest niepewny. Sprawdź wszystkie pola."
            }
            phase = .reviewing
        case .candidates(let found):
            candidates = found
            phase = .choosingCandidate
        case .notFound:
            notice = "Nie rozpoznano adresu odbiorcy. Wpisz go ręcznie."
            phase = .reviewing
        }
    }

    private func fill(with parsed: ParsedAddress) {
        form = AddressForm(address: parsed.address)
        var fields: Set<AddressForm.Field> = []
        if parsed.warnings.contains(.postalCodeCorrected) { fields.insert(.postalCode) }
        if parsed.warnings.contains(.missingBuildingNumber) { fields.insert(.buildingNumber) }
        parserFlaggedFields = fields
    }
}
