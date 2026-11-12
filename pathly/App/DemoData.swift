#if DEBUG
import Foundation
import SwiftData

/// Zmyślone dane do pokazania aplikacji (zrzuty ekranu do README).
///
/// Uruchomienie: `xcrun simctl launch booted com.mikolajbozko.pathly -demo`.
/// Aplikacja startuje wtedy z bazą danych w pamięci — prawdziwe dane na
/// urządzeniu pozostają nietknięte, a po zamknięciu nic nie zostaje.
enum DemoData {
    static let launchArgument = "-demo"

    static var isRequested: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    static let base = BaseLocation(
        address: Address(street: "ul. Rakowicka", buildingNumber: "10", postalCode: "31-511", city: "Kraków"),
        coordinate: Coordinate(latitude: 50.0700, longitude: 19.9500)
    )

    /// Adresy fikcyjnych odbiorców ze współrzędnymi — bez zapytań do geokodera.
    static let parcels: [(Address, Coordinate)] = [
        (Address(street: "Rynek Główny", buildingNumber: "1", postalCode: "31-042", city: "Kraków"), Coordinate(latitude: 50.0617, longitude: 19.9373)),
        (Address(street: "ul. Floriańska", buildingNumber: "15", apartmentNumber: "3", postalCode: "31-019", city: "Kraków"), Coordinate(latitude: 50.0640, longitude: 19.9405)),
        (Address(street: "ul. Karmelicka", buildingNumber: "30", postalCode: "31-128", city: "Kraków"), Coordinate(latitude: 50.0664, longitude: 19.9310)),
        (Address(street: "ul. Dietla", buildingNumber: "50", postalCode: "31-039", city: "Kraków"), Coordinate(latitude: 50.0520, longitude: 19.9440)),
        (Address(street: "ul. Starowiślna", buildingNumber: "60", apartmentNumber: "12", postalCode: "31-035", city: "Kraków"), Coordinate(latitude: 50.0560, longitude: 19.9480)),
        (Address(street: "ul. Mogilska", buildingNumber: "40", postalCode: "31-546", city: "Kraków"), Coordinate(latitude: 50.0670, longitude: 19.9650)),
        (Address(street: "ul. Kalwaryjska", buildingNumber: "20", postalCode: "30-504", city: "Kraków"), Coordinate(latitude: 50.0445, longitude: 19.9440)),
        (Address(street: "ul. Zakopiańska", buildingNumber: "62", postalCode: "30-418", city: "Kraków"), Coordinate(latitude: 50.0180, longitude: 19.9300)),
        (Address(street: "ul. Wielicka", buildingNumber: "28", postalCode: "30-552", city: "Kraków"), Coordinate(latitude: 50.0390, longitude: 19.9700)),
        (Address(street: "ul. Królewska", buildingNumber: "57", postalCode: "30-081", city: "Kraków"), Coordinate(latitude: 50.0750, longitude: 19.9180)),
        (Address(street: "ul. Lea", buildingNumber: "112", postalCode: "30-133", city: "Kraków"), Coordinate(latitude: 50.0750, longitude: 19.9000)),
        (Address(street: "al. Pokoju", buildingNumber: "44", postalCode: "31-564", city: "Kraków"), Coordinate(latitude: 50.0620, longitude: 20.0050)),
        (Address(street: "ul. Kamieńskiego", buildingNumber: "11", postalCode: "30-644", city: "Kraków"), Coordinate(latitude: 50.0300, longitude: 19.9500)),
        (Address(street: "ul. Czarnowiejska", buildingNumber: "50", postalCode: "30-054", city: "Kraków"), Coordinate(latitude: 50.0680, longitude: 19.9100)),
    ]

    static func seed(_ dependencies: AppDependencies) throws {
        try dependencies.baseStore.saveBase(base)
        let store = SwiftDataParcelStore(context: dependencies.modelContainer.mainContext)
        for (address, coordinate) in parcels {
            let id = try store.addParcel(address: address)
            try store.recordGeocoding(.located(coordinate), ofParcel: id, for: address)
        }
    }
}
#endif
