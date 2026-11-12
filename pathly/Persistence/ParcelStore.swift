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
    /// Kurier wskazał położenie ręcznie na mapie, bo geokoder nie znalazł adresu.
    func setManualLocation(_ coordinate: Coordinate, forParcel id: UUID) throws
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

/// Implementacja `ParcelStore`, `GeocodingStore` i `DeliveryStore` na SwiftData.
///
/// Każda zmiana zbioru przesyłek albo ich położenia oznacza bieżącą trasę jako
/// nieaktualną — w tym samym zapisie, więc nie da się o tym zapomnieć.
///
/// Wyszukiwanie po statusie i adresie odbywa się w pamięci, nie w `#Predicate`:
/// predykaty SwiftData słabo radzą sobie z enumami i strukturami `Codable`,
/// a przesyłek na jednej trasie jest najwyżej kilkaset.
final class SwiftDataParcelStore: ParcelStore, GeocodingStore, DeliveryStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func addParcel(address: Address) throws -> UUID {
        let parcel = Parcel(address: address)
        context.insert(parcel)
        try context.invalidateRoute()
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
        try context.invalidateRoute()
        try context.save()
    }

    func deleteParcels(_ ids: Set<UUID>) throws {
        try context.delete(model: Parcel.self, where: #Predicate { ids.contains($0.id) })
        try context.invalidateRoute()
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
        try setLocation(candidate.coordinate, forParcel: id)
    }

    /// Położenie wskazane na mapie obowiązuje dla bieżącego adresu — inna paczka
    /// pod ten sam adres też je przejmie, a zmiana adresu wyśle przesyłkę do geokodowania.
    func setManualLocation(_ coordinate: Coordinate, forParcel id: UUID) throws {
        try setLocation(coordinate, forParcel: id)
    }

    private func setLocation(_ coordinate: Coordinate, forParcel id: UUID) throws {
        guard let parcel = try fetch(id) else { throw ParcelStoreError.parcelNotFound }
        parcel.coordinate = coordinate
        parcel.geocodedAddress = parcel.address
        parcel.geocodingCandidates = []
        parcel.geocodingStatus = .succeeded
        try context.invalidateRoute()
        try context.save()
    }

    // MARK: DeliveryStore

    func routeCandidates() throws -> RouteCandidates {
        let waiting = try fetchAll().filter { $0.deliveryStatus == .pending }
        var candidates = RouteCandidates(stops: [])
        for parcel in waiting {
            switch parcel.geocodingStatus {
            case .succeeded:
                if let coordinate = parcel.coordinate {
                    candidates.stops.append(RouteStop(parcelID: parcel.id, coordinate: coordinate))
                } else {
                    candidates.needingAttention += 1
                }
            case .pending:
                candidates.awaitingGeocoding += 1
            case .notFound, .ambiguous, .failed:
                candidates.needingAttention += 1
            }
        }
        return candidates
    }

    func setDeliveryStatus(_ status: DeliveryStatus, ofParcel id: UUID) throws {
        guard let parcel = try fetch(id) else { throw ParcelStoreError.parcelNotFound }
        parcel.deliveryStatus = status
        try context.save()
    }

    func finishDay() throws -> DaySummary {
        var summary = DaySummary(removed: 0, carriedOver: 0)
        for parcel in try fetchAll() {
            switch parcel.deliveryStatus {
            case .delivered:
                context.delete(parcel)
                summary.removed += 1
            case .notDelivered:
                parcel.deliveryStatus = .pending
                summary.carriedOver += 1
            case .pending:
                break
            }
        }
        try context.delete(model: Route.self)
        try context.save()
        return summary
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
            if parcel.coordinate != coordinate || parcel.geocodingStatus != .succeeded {
                try context.invalidateRoute()
            }
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
