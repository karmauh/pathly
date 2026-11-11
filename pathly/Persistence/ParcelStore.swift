import Foundation
import SwiftData

/// Operacje na przesyłkach wykonywane przez view modele.
///
/// Lista przesyłek czyta dane przez `@Query` (aktualizuje się sama po zmianach),
/// a wszystkie zmiany przechodzą przez ten protokół — dzięki temu logikę
/// zatwierdzania i usuwania można testować bez interfejsu.
protocol ParcelStore {
    @discardableResult
    func addParcel(address: Address) throws -> UUID
    func address(ofParcel id: UUID) throws -> Address?
    func updateAddress(ofParcel id: UUID, to address: Address) throws
    func deleteParcels(_ ids: Set<UUID>) throws
}

enum ParcelStoreError: LocalizedError {
    case parcelNotFound

    var errorDescription: String? {
        "Nie znaleziono przesyłki — mogła zostać usunięta."
    }
}

/// Implementacja `ParcelStore` na SwiftData.
final class SwiftDataParcelStore: ParcelStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func addParcel(address: Address) throws -> UUID {
        let parcel = Parcel(address: address)
        context.insert(parcel)
        try context.save()
        return parcel.id
    }

    func address(ofParcel id: UUID) throws -> Address? {
        try fetch(id)?.address
    }

    /// Zmiana adresu unieważnia poprzednie geokodowanie — przesyłka wraca do kolejki.
    func updateAddress(ofParcel id: UUID, to address: Address) throws {
        guard let parcel = try fetch(id) else { throw ParcelStoreError.parcelNotFound }
        guard parcel.address != address else { return }
        parcel.address = address
        if parcel.geocodedAddress != address {
            parcel.coordinate = nil
            parcel.geocodingStatus = .pending
        }
        try context.save()
    }

    func deleteParcels(_ ids: Set<UUID>) throws {
        try context.delete(model: Parcel.self, where: #Predicate { ids.contains($0.id) })
        try context.save()
    }

    private func fetch(_ id: UUID) throws -> Parcel? {
        var descriptor = FetchDescriptor<Parcel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
