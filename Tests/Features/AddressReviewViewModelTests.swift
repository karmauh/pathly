import Foundation
import Testing
@testable import pathly

@MainActor
@Suite("AddressReviewViewModel")
struct AddressReviewViewModelTests {
    let store = InMemoryParcelStore()

    private func makeViewModel(
        mode: AddressReviewViewModel.Mode = .photo,
        lines: [RecognizedLine] = []
    ) -> AddressReviewViewModel {
        AddressReviewViewModel(mode: mode, recognizer: MockTextRecognizer(result: .success(lines)), store: store)
    }

    @Test("Rozpoznany adres odbiorcy wypełnia formularz")
    func recognizedRecipient() async {
        let viewModel = makeViewModel(lines: LabelFixture.singleColumn.lines)
        #expect(viewModel.phase == .recognizing)

        await viewModel.recognize(makeBlankImage())

        #expect(viewModel.phase == .reviewing)
        #expect(viewModel.form.address == Address(street: "ul. Długa", buildingNumber: "12", apartmentNumber: "4", postalCode: "31-019", city: "Kraków"))
        #expect(viewModel.notice == nil)
        #expect(viewModel.parserFlaggedFields.isEmpty)
        #expect(store.parcels.isEmpty, "Nic nie może się zapisać przed zatwierdzeniem")
    }

    @Test("Poprawiony kod pocztowy jest wyróżniony")
    func correctedPostalCodeIsHighlighted() async {
        let viewModel = makeViewModel(lines: LabelFixture.ocrErrorsInPostalCode.lines)
        await viewModel.recognize(makeBlankImage())
        #expect(viewModel.fieldsToCheck == [.postalCode])
    }

    @Test("Kilku kandydatów — kurier wybiera")
    func candidates() async throws {
        let viewModel = makeViewModel(lines: LabelFixture.noAnchorsTwoAddresses.lines)
        await viewModel.recognize(makeBlankImage())

        #expect(viewModel.phase == .choosingCandidate)
        #expect(viewModel.candidates.count == 2)

        let second = try #require(viewModel.candidates.last)
        viewModel.choose(second)
        #expect(viewModel.phase == .reviewing)
        #expect(viewModel.form.address == second.address)
    }

    @Test("Brak adresu — pusty formularz z komunikatem")
    func notFound() async {
        let viewModel = makeViewModel(lines: LabelFixture.senderOnly.lines)
        await viewModel.recognize(makeBlankImage())
        #expect(viewModel.phase == .reviewing)
        #expect(viewModel.form == AddressForm())
        #expect(viewModel.notice != nil)
        #expect(!viewModel.canApprove)
    }

    @Test("Błąd OCR pozwala wpisać adres ręcznie")
    func recognitionFailure() async {
        let viewModel = AddressReviewViewModel(
            mode: .photo,
            recognizer: MockTextRecognizer(result: .failure(.recognitionFailed)),
            store: store
        )
        await viewModel.recognize(makeBlankImage())
        #expect(viewModel.phase == .reviewing)
        #expect(viewModel.notice != nil)
    }

    @Test("Zatwierdzenie zapisuje przesyłkę")
    func approveSaves() async {
        let viewModel = makeViewModel(lines: LabelFixture.singleColumn.lines)
        await viewModel.recognize(makeBlankImage())

        #expect(viewModel.approve())
        #expect(Array(store.parcels.values) == [viewModel.form.address])
    }

    @Test("Niepoprawny adres nie zapisuje się i wyróżnia błędne pola")
    func approveInvalid() {
        let viewModel = makeViewModel(mode: .manual)
        viewModel.form.city = "Kraków"

        #expect(!viewModel.approve())
        #expect(store.parcels.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.fieldsToCheck == [.buildingNumber, .postalCode])
    }

    @Test("Błąd zapisu nie zamyka ekranu")
    func approveStoreFailure() {
        store.shouldFail = true
        let viewModel = makeViewModel(mode: .manual)
        viewModel.form = AddressForm(address: Address(street: "Polna", buildingNumber: "2", postalCode: "90-001", city: "Łódź"))
        #expect(!viewModel.approve())
        #expect(viewModel.errorMessage != nil)
    }

    @Test("Edycja wczytuje i aktualizuje adres przesyłki")
    func editExisting() throws {
        let original = Address(street: "Polna", buildingNumber: "2", postalCode: "90-001", city: "Łódź")
        let id = try store.addParcel(address: original)
        let viewModel = makeViewModel(mode: .edit(id))

        viewModel.load()
        #expect(viewModel.form.address == original)
        #expect(viewModel.phase == .reviewing)

        viewModel.form.buildingNumber = "4"
        #expect(viewModel.approve())
        #expect(store.parcels[id]?.buildingNumber == "4")
        #expect(store.parcels.count == 1)
    }
}
