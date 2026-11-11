import Foundation

/// Stan formularza adresu — wspólny dla ustawień bazy i podglądu przesyłki.
///
/// Pola są zwykłymi `String`, bo tak wiążą się z `TextField`; `address`
/// zamienia je na znormalizowany `Address`.
nonisolated struct AddressForm: Hashable, Sendable {
    enum Field: Hashable, Sendable, CaseIterable {
        case street, buildingNumber, apartmentNumber, postalCode, city
    }

    var street = ""
    var buildingNumber = ""
    var apartmentNumber = ""
    var postalCode = ""
    var city = ""

    init() {}

    init(address: Address) {
        street = address.street
        buildingNumber = address.buildingNumber
        apartmentNumber = address.apartmentNumber ?? ""
        postalCode = address.postalCode
        city = address.city
    }

    var address: Address {
        Address(
            street: street,
            buildingNumber: buildingNumber,
            apartmentNumber: apartmentNumber,
            postalCode: postalCode,
            city: city
        ).normalized()
    }

    var validationErrors: [Address.ValidationError] {
        address.validationErrors
    }

    /// Pola, których dotyczą błędy walidacji — do podświetlenia w widoku.
    var invalidFields: Set<Field> {
        Set(validationErrors.map { error in
            switch error {
            case .missingBuildingNumber: .buildingNumber
            case .missingCity: .city
            case .invalidPostalCode: .postalCode
            }
        })
    }
}
