import Testing
@testable import pathly

@Suite("Address")
struct AddressTests {
    @Test("Linia ulicy z numerem lokalu")
    func streetLineWithApartment() {
        let address = Address(street: "ul. Długa", buildingNumber: "12A", apartmentNumber: "4", postalCode: "00-238", city: "Warszawa")
        #expect(address.streetLine == "ul. Długa 12A/4")
        #expect(address.singleLine == "ul. Długa 12A/4, 00-238 Warszawa")
    }

    @Test("Adres bez ulicy używa nazwy miejscowości")
    func addressWithoutStreet() {
        let address = Address(street: "", buildingNumber: "7", postalCode: "05-532", city: "Wólka Kosowska")
        #expect(address.streetLine == "Wólka Kosowska 7")
    }

    @Test("Zapytanie geokodujące pomija lokal i dodaje kraj")
    func geocodingQuery() {
        let address = Address(street: "ul. Długa", buildingNumber: "12", apartmentNumber: "4", postalCode: "00-238", city: "Warszawa")
        #expect(address.geocodingQuery == "ul. Długa 12, 00-238 Warszawa, Polska")
    }

    @Test("Normalizacja przycina i scala spacje, pusty lokal to nil")
    func normalization() {
        let address = Address(street: "  ul.   Długa ", buildingNumber: " 12 ", apartmentNumber: "  ", postalCode: " 00-238", city: "Warszawa  ")
            .normalized()
        #expect(address == Address(street: "ul. Długa", buildingNumber: "12", apartmentNumber: nil, postalCode: "00-238", city: "Warszawa"))
    }

    @Test("Poprawny adres nie ma błędów walidacji")
    func validAddress() {
        let address = Address(street: "", buildingNumber: "1", postalCode: "30-001", city: "Kraków")
        #expect(address.validationErrors.isEmpty)
    }

    @Test("Brakujące pola i zły kod pocztowy", arguments: ["", "00238", "0-0238", "00-23", "AB-123"])
    func invalidAddress(postalCode: String) {
        let address = Address(street: "ul. Długa", buildingNumber: "", postalCode: postalCode, city: "")
        #expect(address.validationErrors == [.missingBuildingNumber, .missingCity, .invalidPostalCode])
    }
}
