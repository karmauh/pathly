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
    func geocodingStatus(ofParcel id: UUID) throws -> GeocodingStatus?
    /// Miejsca do wyboru, gdy adres przesyłki okazał się niejednoznaczny.
    func geocodingCandidates(ofParcel id: UUID) throws -> [GeocodingCandidate]
    /// Kurier wskazał właściwe miejsce spośród kandydatów.
    func chooseLocation(_ candidate: GeocodingCandidate, forParcel id: UUID) throws
}

/// Operacje potrzebne kolejce geokodowania.
protocol GeocodingStore {
    /// Identyfikatory przesyłek o danym statusie, od najstarszej.
    func parcelIDs(withStatus status: GeocodingStatus) throws -> [UUID]
    func address(ofParcel id: UUID) throws -> Address?
    /// Współrzędne ustalone już wcześniej dla tego samego adresu (tej lub innej
    /// przesyłki) — pozwalają pominąć zapytanie do geokodera.
    func knownCoordinate(for address: Address) throws -> Coordinate?
    /// Zapisuje wynik, o ile przesyłka nadal istnieje i ma ten sam adres, dla
    /// którego pytaliśmy. Zwraca `false`, gdy wynik jest już nieaktualny.
    @discardableResult
    func recordGeocoding(_ outcome: GeocodingOutcome, ofParcel id: UUID, for address: Address) throws -> Bool
}

enum ParcelStoreError: LocalizedError {
    case parcelNotFound

    var errorDescription: String? {
        "Nie znaleziono przesyłki — mogła zostać usunięta."
    }
}

/// Implementacja `ParcelStore` i `GeocodingStore` na SwiftData.
///
/// Wyszukiwanie po statusie i adresie odbywa się w pamięci, nie w `#Predicate`:
/// predykaty SwiftData słabo radzą sobie z enumami i strukturami `Codable`,
/// a przesyłek na jednej trasie jest najwyżej kilkaset.
final class SwiftDataParcelStore: ParcelStore, GeocodingStore {
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

    /// Zmiana adresu unieważnia geokodowanie — przesyłka wraca do kolejki.
    /// Wyjątek: powrót do adresu, dla którego mamy już współrzędne.
    func updateAddress(ofParcel id: UUID, to address: Address) throws {
        guard let parcel = try fetch(id) else { throw ParcelStoreError.parcelNotFound }
        guard parcel.address != address else { return }
        parcel.address = address
        parcel.geocodingCandidates = []
        let hasCoordinate = parcel.geocodedAddress == address && parcel.coordinate != nil
        parcel.geocodingStatus = hasCoordinate ? .succeeded : .pending
        try context.save()
    }

    func deleteParcels(_ ids: Set<UUID>) throws {
        try context.delete(model: Parcel.self, where: #Predicate { ids.contains($0.id) })
        try context.save()
    }

    func geocodingStatus(ofParcel id: UUID) throws -> GeocodingStatus? {
        try fetch(id)?.geocodingStatus
    }

    func geocodingCandidates(ofParcel id: UUID) throws -> [GeocodingCandidate] {
        guard let parcel = try fetch(id), parcel.geocodingStatus == .ambiguous else { return [] }
        return parcel.geocodingCandidates
    }

    func chooseLocation(_ candidate: GeocodingCandidate, forParcel id: UUID) throws {
        guard let parcel = try fetch(id) else { throw ParcelStoreError.parcelNotFound }
        parcel.coordinate = candidate.coordinate
        parcel.geocodedAddress = parcel.address
        parcel.geocodingCandidates = []
        parcel.geocodingStatus = .succeeded
        try context.save()
    }

    // MARK: GeocodingStore

    func parcelIDs(withStatus status: GeocodingStatus) throws -> [UUID] {
        try fetchAll().filter { $0.geocodingStatus == status }.map(\.id)
    }

    func knownCoordinate(for address: Address) throws -> Coordinate? {
        try fetchAll().first { $0.geocodedAddress == address && $0.coordinate != nil }?.coordinate
    }

    @discardableResult
    func recordGeocoding(_ outcome: GeocodingOutcome, ofParcel id: UUID, for address: Address) throws -> Bool {
        guard let parcel = try fetch(id), parcel.address == address else { return false }
        parcel.geocodingCandidates = []
        switch outcome {
        case .located(let coordinate):
            parcel.coordinate = coordinate
            parcel.geocodedAddress = address
            parcel.geocodingStatus = .succeeded
        case .notFound:
            parcel.geocodingStatus = .notFound
        case .ambiguous(let candidates):
            parcel.geocodingCandidates = candidates
            parcel.geocodingStatus = .ambiguous
        case .failed:
            parcel.geocodingStatus = .failed
        }
        try context.save()
        return true
    }

    // MARK: Pomocnicze

    private func fetch(_ id: UUID) throws -> Parcel? {
        var descriptor = FetchDescriptor<Parcel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchAll() throws -> [Parcel] {
        try context.fetch(FetchDescriptor<Parcel>(sortBy: [SortDescriptor(\.createdAt)]))
    }
}
