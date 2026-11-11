import Foundation
import SwiftData

/// Zapisana baza kuriera (model SwiftData).
///
/// Aplikacja przechowuje co najwyżej jeden rekord — pilnuje tego `SwiftDataBaseStore`.
@Model
final class Base {
    var address: Address
    var coordinate: Coordinate
    var updatedAt: Date

    init(address: Address, coordinate: Coordinate, updatedAt: Date = .now) {
        self.address = address
        self.coordinate = coordinate
        self.updatedAt = updatedAt
    }

    var location: BaseLocation {
        BaseLocation(address: address, coordinate: coordinate)
    }
}
