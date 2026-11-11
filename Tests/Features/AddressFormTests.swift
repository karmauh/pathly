import Testing
@testable import pathly

@Suite("AddressForm")
struct AddressFormTests {
    @Test("Wypełnienie z adresu i powrót do adresu")
    func roundTrip() {
        let address = Address(street: "ul. Długa", buildingNumber: "12", apartmentNumber: "4", postalCode: "31-019", city: "Kraków")
        #expect(AddressForm(address: address).address == address)
    }

    @Test("Adres z formularza jest znormalizowany")
    func normalizedAddress() {
        var form = AddressForm()
        form.street = "  ul.  Długa "
        form.buildingNumber = "12"
        form.apartmentNumber = " "
        form.postalCode = "31-019"
        form.city = "Kraków "
        #expect(form.address == Address(street: "ul. Długa", buildingNumber: "12", postalCode: "31-019", city: "Kraków"))
    }

    @Test("Niepoprawne pola")
    func invalidFields() {
        var form = AddressForm()
        form.postalCode = "31019"
        #expect(form.invalidFields == [.buildingNumber, .city, .postalCode])
    }
}
