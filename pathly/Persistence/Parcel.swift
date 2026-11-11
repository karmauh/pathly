import Foundation
import SwiftData

/// Przesyłka do doręczenia (model SwiftData).
///
/// Schemat przygotowany w etapie 1; wypełniany od etapu 3 (dodawanie ze zdjęcia)
/// i 4 (geokodowanie).
@Model
final class Parcel {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var address: Address
    /// Współrzędne; `nil`, dopóki geokodowanie się nie powiedzie.
    var coordinate: Coordinate?
    /// Adres, dla którego wyznaczono `coordinate`. Pozwala nie geokodować
    /// ponownie niezmienionego adresu.
    var geocodedAddress: Address?
    var geocodingStatus: GeocodingStatus
    var deliveryStatus: DeliveryStatus
    /// Opcjonalne zdjęcie etykiety (JPEG), trzymane poza główną bazą.
    @Attribute(.externalStorage) var labelPhoto: Data?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        address: Address,
        labelPhoto: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.address = address
        self.coordinate = nil
        self.geocodedAddress = nil
        self.geocodingStatus = .pending
        self.deliveryStatus = .pending
        self.labelPhoto = labelPhoto
    }
}
