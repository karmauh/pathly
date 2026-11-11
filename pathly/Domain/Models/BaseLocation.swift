import Foundation

/// Baza kuriera: adres i jego współrzędne. Start i koniec każdej trasy.
///
/// Wartość domenowa niezależna od SwiftData — warstwa persystencji mapuje ją
/// na model `Base`, a view modele pracują tylko na tym typie.
nonisolated struct BaseLocation: Hashable, Codable, Sendable {
    var address: Address
    var coordinate: Coordinate
}
