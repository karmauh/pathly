import Foundation
import Testing
@testable import pathly

@MainActor
@Suite("AddressReviewViewModel")
struct AddressReviewViewModelTests {
    let store = InMemoryParcelStore()
    let scheduler = RecordingGeocodingScheduler()
    let polna = Address(street: "Polna", buildingNumber: "2", postalCode: "90-001", city: "Łódź")

    private func makeViewModel(
        mode: AddressReviewViewModel.Mode = .photo,
        lines: [RecognizedLine] = []
    ) -> AddressReviewViewModel {
        AddressReviewViewModel(mode: mode, recognizer: MockTextRecognizer(result: .success(lines)), store: store, geocoding: scheduler)
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
            store: store,
            geocoding: scheduler
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
        #expect(scheduler.enqueued == Array(store.parcels.keys), "Zatwierdzona przesyłka trafia do kolejki geokodowania")
    }

    @Test("Niepoprawny adres nie zapisuje się i wyróżnia błędne pola")
    func approveInvalid() {
        let viewModel = makeViewModel(mode: .manual)
        viewModel.form.city = "Kraków"

        #expect(!viewModel.approve())
        #expect(store.parcels.isEmpty)
        #expect(scheduler.enqueued.isEmpty)
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
        #expect(scheduler.enqueued.isEmpty)
    }

    @Test("Edycja wczytuje i aktualizuje adres przesyłki")
    func editExisting() throws {
        let original = polna
        let id = try store.addParcel(address: original)
        let viewModel = makeViewModel(mode: .edit(id))

        viewModel.load()
        #expect(viewModel.form.address == original)
        #expect(viewModel.phase == .reviewing)

        viewModel.form.buildingNumber = "4"
        #expect(viewModel.approve())
        #expect(store.parcels[id]?.buildingNumber == "4")
        #expect(store.parcels.count == 1)
        #expect(scheduler.enqueued == [id])
    }

    @Test("Niejednoznaczny adres — kurier wybiera miejsce")
    func chooseAmbiguousLocation() throws {
        let id = try store.addParcel(address: polna)
        let candidates = [
            GeocodingCandidate(coordinate: Coordinate(latitude: 51.76, longitude: 19.45), label: "Polna 2, Łódź"),
            GeocodingCandidate(coordinate: Coordinate(latitude: 51.70, longitude: 19.30), label: "Polna 2, Łódź-Ruda"),
        ]
        store.statuses[id] = .ambiguous
        store.candidates[id] = candidates
        let viewModel = makeViewModel(mode: .edit(id))

        viewModel.load()
        #expect(viewModel.canChooseLocation)
        #expect(viewModel.chooseLocation(candidates[1]))
        #expect(store.chosenLocations[id] == candidates[1])
    }

    @Test("Po zmianie adresu kandydaci miejsc znikają")
    func editedAddressHidesLocationCandidates() throws {
        let id = try store.addParcel(address: polna)
        store.statuses[id] = .ambiguous
        store.candidates[id] = [GeocodingCandidate(coordinate: Coordinate(latitude: 51.76, longitude: 19.45), label: "Polna 2")]
        let viewModel = makeViewModel(mode: .edit(id))

        viewModel.load()
        viewModel.form.buildingNumber = "3"
        #expect(!viewModel.canChooseLocation)
    }

    @Test("Edycja nieznalezionego adresu wyjaśnia problem")
    func notFoundNotice() throws {
        let id = try store.addParcel(address: polna)
        store.statuses[id] = .notFound
        let viewModel = makeViewModel(mode: .edit(id))

        viewModel.load()
        #expect(viewModel.geocodingProblem != nil)
        #expect(!viewModel.canChooseLocation)

        viewModel.form.city = "Zgierz"
        #expect(viewModel.geocodingProblem == nil, "Po zmianie adresu stary problem nie dotyczy")
    }

    @Test("Zatwierdzenie nieznalezionego adresu bez zmian ponawia geokodowanie")
    func reapproveRetriesGeocoding() throws {
        let id = try store.addParcel(address: polna)
        store.statuses[id] = .notFound
        let viewModel = makeViewModel(mode: .edit(id))
        viewModel.load()

        #expect(viewModel.approve())
        #expect(scheduler.enqueued == [id])
    }

    @Test("Nieznaleziony adres — kurier wskazuje miejsce na mapie")
    func manualLocation() throws {
        let id = try store.addParcel(address: polna)
        store.statuses[id] = .notFound
        let viewModel = makeViewModel(mode: .edit(id))
        viewModel.load()
        #expect(viewModel.canPickLocationOnMap)

        let pin = Coordinate(latitude: 51.75, longitude: 19.45)
        #expect(viewModel.setManualLocation(pin))
        #expect(store.manualLocations[id] == pin)
    }

    @Test("Wskazanie na mapie tylko dla zapisanego adresu przesyłki bez położenia")
    func manualLocationAvailability() throws {
        let located = try store.addParcel(address: polna)
        store.statuses[located] = .succeeded
        let viewModel = makeViewModel(mode: .edit(located))
        viewModel.load()
        #expect(!viewModel.canPickLocationOnMap, "Położenie już jest")

        let missing = try store.addParcel(address: polna)
        store.statuses[missing] = .notFound
        let editing = makeViewModel(mode: .edit(missing))
        editing.load()
        editing.form.buildingNumber = "99"
        #expect(!editing.canPickLocationOnMap, "Nowy adres najpierw trafia do geokodera")

        #expect(!makeViewModel(mode: .manual).canPickLocationOnMap)
    }
}
