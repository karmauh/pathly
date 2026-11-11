import Foundation
import SwiftData

/// Przesyłka do doręczenia (model SwiftData).
///
/// Zdjęcie etykiety nie jest przechowywane: kurier weryfikuje adres od razu po
/// zrobieniu zdjęcia, a paczka i tak jest fizycznie w aucie.
@Model
final class Parcel {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var address: Address
    /// Współrzędne adresu `geocodedAddress`. Obowiązują tylko przy statusie
    /// `.succeeded` — po zmianie adresu zostają, żeby powrót do poprzedniego
    /// adresu nie wymagał ponownego zapytania.
    var coordinate: Coordinate?
    /// Adres, dla którego wyznaczono `coordinate`. Pozwala nie geokodować
    /// ponownie niezmienionego adresu.
    var geocodedAddress: Address?
    var geocodingStatus: GeocodingStatus
    /// Pasujące miejsca, gdy adres jest niejednoznaczny — kurier wybiera jedno
    /// z nich bez ponownego zapytania.
    var geocodingCandidates: [GeocodingCandidate] = []
    var deliveryStatus: DeliveryStatus

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        address: Address
    ) {
        self.id = id
        self.createdAt = createdAt
        self.address = address
        self.coordinate = nil
        self.geocodedAddress = nil
        self.geocodingStatus = .pending
        self.geocodingCandidates = []
        self.deliveryStatus = .pending
    }
}
