import CoreGraphics
import Foundation
import Observation

/// Logika ekranu podglądu adresu: OCR zdjęcia, wypełnienie formularza wynikiem
/// parsera, wybór kandydata i zatwierdzenie przesyłki.
///
/// Nic nie trafia do bazy bez wywołania `approve()` przez kuriera.
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

    private let recognizer: any TextRecognizer
    private let parser: AddressParser
    private let store: any ParcelStore

    init(mode: Mode, recognizer: any TextRecognizer, parser: AddressParser = AddressParser(), store: any ParcelStore) {
        self.mode = mode
        self.recognizer = recognizer
        self.parser = parser
        self.store = store
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

    /// Wczytuje adres edytowanej przesyłki.
    func load() {
        guard case .edit(let id) = mode else { return }
        do {
            if let address = try store.address(ofParcel: id) {
                form = AddressForm(address: address)
            }
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
            switch mode {
            case .photo, .manual:
                try store.addParcel(address: form.address)
            case .edit(let id):
                try store.updateAddress(ofParcel: id, to: form.address)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
