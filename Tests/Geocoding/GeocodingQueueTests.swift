import Foundation
import SwiftData
import Testing
@testable import pathly

/// Geokoder ze scenariuszem: kolejne odpowiedzi z listy, potem wynik domyślny.
/// Liczy zapytania wykonywane jednocześnie, żeby sprawdzić sekwencyjność kolejki.
@MainActor
final class ScriptedGeocoder: Geocoder {
    var responses: [Result<GeocodingResult, GeocodingError>] = []
    /// Wywoływane na początku każdego zapytania (np. by zmienić dane w jego trakcie).
    var onGeocode: ((Address) -> Void)?
    private(set) var requests: [Address] = []
    private(set) var maxInFlight = 0
    private var inFlight = 0

    /// Współrzędne zależne od numeru budynku — łatwo sprawdzić, który adres zapisano.
    static func coordinate(for address: Address) -> Coordinate {
        Coordinate(latitude: 50 + (Double(address.buildingNumber) ?? 0) / 100, longitude: 20)
    }

    func geocode(_ address: Address) async throws -> GeocodingResult {
        requests.append(address)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        onGeocode?(address)
        // Oddajemy sterowanie — równoległe zapytania miałyby szansę się nałożyć.
        await Task.yield()
        await Task.yield()
        if !responses.isEmpty {
            return try responses.removeFirst().get()
        }
        return .found(GeocodingCandidate(coordinate: Self.coordinate(for: address), label: address.singleLine))
    }
}

@MainActor
@Suite("GeocodingQueue")
struct GeocodingQueueTests {
    let container: ModelContainer
    let store: SwiftDataParcelStore
    let geocoder = ScriptedGeocoder()
    /// Opóźnienia, na które kolejka chciała czekać (bez faktycznego czekania).
    let sleeps = SleepRecorder()

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        store = SwiftDataParcelStore(context: container.mainContext)
    }

    final class SleepRecorder {
        var delays: [Duration] = []
    }

    /// - Parameters:
    ///   - store: magazyn kolejki; domyślnie prawdziwy `SwiftDataParcelStore`.
    ///   - onSleep: wywoływane przy każdym czekaniu (po zapisaniu opóźnienia) —
    ///     może zmienić dane albo rzucić, jak anulowany `Task.sleep`.
    private func makeQueue(
        policy: GeocodingQueue.RetryPolicy = .init(),
        store: (any GeocodingStore)? = nil,
        onSleep: (() throws -> Void)? = nil
    ) -> GeocodingQueue {
        let sleeps = sleeps
        return GeocodingQueue(geocoder: geocoder, store: store ?? self.store, policy: policy) {
            sleeps.delays.append($0)
            try onSleep?()
        }
    }

    private func address(_ number: Int) -> Address {
        Address(street: "ul. Długa", buildingNumber: "\(number)", postalCode: "31-019", city: "Kraków")
    }

    private func parcel(_ id: UUID) throws -> Parcel {
        try #require(try container.mainContext.fetch(FetchDescriptor<Parcel>(predicate: #Predicate { $0.id == id })).first)
    }

    @Test("Przesyłki są geokodowane po kolei, jedno zapytanie naraz")
    func sequential() async throws {
        let queue = makeQueue()
        let addresses = [address(1), address(2), address(3)]
        let ids = try addresses.map { try store.addParcel(address: $0) }

        ids.forEach(queue.enqueue)
        await queue.waitUntilIdle()

        #expect(geocoder.requests == addresses)
        #expect(geocoder.maxInFlight == 1)
        for (id, address) in zip(ids, addresses) {
            let saved = try parcel(id)
            #expect(saved.geocodingStatus == .succeeded)
            #expect(saved.coordinate == ScriptedGeocoder.coordinate(for: address))
        }
    }

    @Test("Postęp liczy przesyłki bieżącej serii i zeruje się po zakończeniu")
    func progress() async throws {
        let queue = makeQueue()
        var snapshots: [[Int]] = []
        geocoder.onGeocode = { _ in snapshots.append([queue.completed, queue.total]) }
        let ids = try (1...3).map { try store.addParcel(address: address($0)) }

        ids.forEach(queue.enqueue)
        #expect(queue.isRunning)
        await queue.waitUntilIdle()

        #expect(snapshots == [[0, 3], [1, 3], [2, 3]])
        #expect(!queue.isRunning)
        #expect(queue.total == 0)
    }

    @Test("Po błędzie limitu kolejka czeka coraz dłużej i ponawia")
    func rateLimitBackoff() async throws {
        let queue = makeQueue()
        geocoder.responses = [.failure(.rateLimited), .failure(.rateLimited)]
        var waitingFlags: [Bool] = []
        geocoder.onGeocode = { _ in waitingFlags.append(queue.isWaitingForRateLimit) }
        let id = try store.addParcel(address: address(1))

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(sleeps.delays == [.seconds(2), .seconds(4)])
        #expect(waitingFlags == [false, true, true])
        #expect(!queue.isWaitingForRateLimit)
        #expect(try parcel(id).geocodingStatus == .succeeded)
    }

    @Test("Po wyczerpaniu prób status błędu; ręczne ponowienie działa")
    func retriesExhausted() async throws {
        var policy = GeocodingQueue.RetryPolicy()
        policy.rateLimitRetries = 2
        let queue = makeQueue(policy: policy)
        geocoder.responses = Array(repeating: .failure(.rateLimited), count: 3)
        let id = try store.addParcel(address: address(1))

        queue.enqueue(id)
        await queue.waitUntilIdle()
        #expect(geocoder.requests.count == 3)
        #expect(try parcel(id).geocodingStatus == .failed)

        queue.retryFailed()
        await queue.waitUntilIdle()
        #expect(try parcel(id).geocodingStatus == .succeeded)
    }

    @Test("Błąd sieci jest ponawiany ograniczoną liczbę razy")
    func networkFailure() async throws {
        let queue = makeQueue()
        geocoder.responses = Array(repeating: .failure(.failed("offline")), count: 3)
        let id = try store.addParcel(address: address(1))

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(geocoder.requests.count == 3)
        #expect(sleeps.delays == [.seconds(2), .seconds(4)])
        #expect(try parcel(id).geocodingStatus == .failed)
    }

    @Test("Brak wyniku i niejednoznaczność są zapisywane")
    func notFoundAndAmbiguous() async throws {
        let queue = makeQueue()
        let candidates = [
            GeocodingCandidate(coordinate: Coordinate(latitude: 50, longitude: 20), label: "A"),
            GeocodingCandidate(coordinate: Coordinate(latitude: 51, longitude: 21), label: "B"),
        ]
        geocoder.responses = [.success(.notFound), .success(.ambiguous(candidates))]
        let missing = try store.addParcel(address: address(1))
        let ambiguous = try store.addParcel(address: address(2))

        queue.enqueue(missing)
        queue.enqueue(ambiguous)
        await queue.waitUntilIdle()

        #expect(try parcel(missing).geocodingStatus == .notFound)
        #expect(try parcel(ambiguous).geocodingStatus == .ambiguous)
        #expect(try parcel(ambiguous).geocodingCandidates == candidates)
        #expect(sleeps.delays.isEmpty, "Brak wyniku to nie błąd — bez ponawiania")
    }

    @Test("Nieznaleziony adres zatwierdzony ponownie bez zmian jest geokodowany od nowa")
    func notFoundIsRetriedOnEnqueue() async throws {
        let queue = makeQueue()
        geocoder.responses = [.success(.notFound)]
        let id = try store.addParcel(address: address(7))
        queue.enqueue(id)
        await queue.waitUntilIdle()
        #expect(try parcel(id).geocodingStatus == .notFound)

        // Kurier otwiera przesyłkę i zatwierdza ją bez zmian (np. po poprawce geokodera).
        try store.updateAddress(ofParcel: id, to: address(7))
        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(geocoder.requests.count == 2)
        #expect(try parcel(id).geocodingStatus == .succeeded)
    }

    @Test("Znany adres nie jest geokodowany ponownie")
    func knownAddressSkipsRequest() async throws {
        let queue = makeQueue()
        let first = try store.addParcel(address: address(1))
        queue.enqueue(first)
        await queue.waitUntilIdle()
        #expect(geocoder.requests.count == 1)

        // Ta sama przesyłka zatwierdzona ponownie i druga paczka pod ten sam adres.
        let second = try store.addParcel(address: address(1))
        queue.enqueue(first)
        queue.enqueue(second)
        await queue.waitUntilIdle()

        #expect(geocoder.requests.count == 1)
        #expect(try parcel(second).geocodingStatus == .succeeded)
        #expect(try parcel(second).coordinate == ScriptedGeocoder.coordinate(for: address(1)))
    }

    @Test("Zmiana adresu w trakcie zapytania — stary wynik jest odrzucany")
    func addressChangedDuringRequest() async throws {
        let queue = makeQueue()
        let id = try store.addParcel(address: address(1))
        geocoder.onGeocode = { [store] requested in
            guard requested == address(1) else { return }
            try? store.updateAddress(ofParcel: id, to: address(2))
            queue.enqueue(id)
        }

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(geocoder.requests == [address(1), address(2)])
        #expect(try parcel(id).coordinate == ScriptedGeocoder.coordinate(for: address(2)))
        #expect(try parcel(id).geocodingStatus == .succeeded)
    }

    @Test("Przesyłka usunięta przed swoją kolejką jest pomijana")
    func deletedParcelIsSkipped() async throws {
        let queue = makeQueue()
        let first = try store.addParcel(address: address(1))
        let second = try store.addParcel(address: address(2))
        geocoder.onGeocode = { [store] _ in try? store.deleteParcels([second]) }

        queue.enqueue(first)
        queue.enqueue(second)
        await queue.waitUntilIdle()

        #expect(geocoder.requests == [address(1)])
    }

    @Test("Po uruchomieniu aplikacji kolejka podejmuje oczekujące przesyłki")
    func resumePending() async throws {
        let queue = makeQueue()
        let pending = try store.addParcel(address: address(1))
        let failed = try store.addParcel(address: address(2))
        try store.recordGeocoding(.failed, ofParcel: failed, for: address(2))

        queue.resumePending()
        await queue.waitUntilIdle()

        #expect(geocoder.requests == [address(1)])
        #expect(try parcel(pending).geocodingStatus == .succeeded)
        #expect(try parcel(failed).geocodingStatus == .failed, "Błędy techniczne ponawia kurier")
    }

    @Test("Ta sama przesyłka nie trafia do kolejki dwa razy")
    func noDuplicates() async throws {
        let queue = makeQueue()
        let first = try store.addParcel(address: address(1))
        let second = try store.addParcel(address: address(2))

        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(second)
        #expect(queue.total == 2)
        #expect(queue.isScheduled(second))
        await queue.waitUntilIdle()
        #expect(geocoder.requests.count == 2)
        #expect(!queue.isScheduled(second))
    }

    // MARK: Anulowanie, błędy magazynu, wyczerpany limit

    @Test("Anulowane czekanie niczego nie zapisuje — przesyłka zostaje oczekująca")
    func cancelledWaitKeepsPending() async throws {
        let queue = makeQueue(onSleep: { throw CancellationError() })
        geocoder.responses = [.failure(.rateLimited)]
        let id = try store.addParcel(address: address(1))

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(geocoder.requests.count == 1)
        #expect(try parcel(id).geocodingStatus == .pending)
        #expect(!queue.isWaitingForRateLimit)
        #expect(!queue.isRunning)
    }

    @Test("Błąd odczytu adresu pomija przesyłkę, a kolejka idzie dalej")
    func addressReadFailure() async throws {
        let first = try store.addParcel(address: address(1))
        let second = try store.addParcel(address: address(2))
        let failing = FailingGeocodingStore(base: store)
        failing.failingAddressReads = [first]
        let queue = makeQueue(store: failing)

        queue.enqueue(first)
        queue.enqueue(second)
        await queue.waitUntilIdle()

        #expect(geocoder.requests == [address(2)])
        #expect(try parcel(first).geocodingStatus == .pending)
        #expect(try parcel(second).geocodingStatus == .succeeded)
    }

    @Test("Błąd zapisu wyniku nie zatrzymuje kolejki")
    func recordFailure() async throws {
        let first = try store.addParcel(address: address(1))
        let second = try store.addParcel(address: address(2))
        let failing = FailingGeocodingStore(base: store)
        failing.failingRecords = [first]
        let queue = makeQueue(store: failing)

        queue.enqueue(first)
        queue.enqueue(second)
        await queue.waitUntilIdle()

        #expect(geocoder.requests.count == 2)
        #expect(try parcel(first).geocodingStatus == .pending, "Podejmie ją resumePending")
        #expect(try parcel(second).geocodingStatus == .succeeded)
        #expect(!queue.isRunning)
        #expect(queue.total == 0)
    }

    @Test("Błąd sprawdzania znanych współrzędnych kończy się zwykłym zapytaniem")
    func knownCoordinateFailure() async throws {
        let id = try store.addParcel(address: address(1))
        let failing = FailingGeocodingStore(base: store)
        failing.failKnownCoordinate = true
        let queue = makeQueue(store: failing)

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(geocoder.requests == [address(1)])
        #expect(try parcel(id).geocodingStatus == .succeeded)
    }

    @Test("Wyczerpany limit oznacza resztę serii jako błąd bez zapytań; ponowienie obejmuje wszystkie")
    func rateLimitExhaustionStopsSeries() async throws {
        var policy = GeocodingQueue.RetryPolicy()
        policy.rateLimitRetries = 1
        let queue = makeQueue(policy: policy)

        // Adres o znanych współrzędnych nie potrzebuje zapytania, więc dostanie je mimo limitu.
        let located = try store.addParcel(address: address(9))
        queue.enqueue(located)
        await queue.waitUntilIdle()
        #expect(geocoder.requests.count == 1)

        geocoder.responses = [.failure(.rateLimited), .failure(.rateLimited)]
        let first = try store.addParcel(address: address(1))
        let second = try store.addParcel(address: address(2))
        let sameAsLocated = try store.addParcel(address: address(9))
        let third = try store.addParcel(address: address(3))
        [first, second, sameAsLocated, third].forEach(queue.enqueue)
        await queue.waitUntilIdle()

        #expect(geocoder.requests.count == 3, "Tylko pierwsza przesyłka i jej jedno ponowienie")
        #expect(sleeps.delays == [.seconds(2)])
        #expect(try parcel(first).geocodingStatus == .failed)
        #expect(try parcel(second).geocodingStatus == .failed)
        #expect(try parcel(third).geocodingStatus == .failed)
        #expect(try parcel(sameAsLocated).geocodingStatus == .succeeded)

        queue.retryFailed()
        await queue.waitUntilIdle()
        #expect(geocoder.requests.count == 6)
        #expect(try parcel(first).geocodingStatus == .succeeded)
        #expect(try parcel(second).geocodingStatus == .succeeded)
        #expect(try parcel(third).geocodingStatus == .succeeded)
    }

    @Test("Zmiana adresu podczas czekania przerywa ponawianie starego adresu")
    func addressChangedDuringBackoff() async throws {
        let id = try store.addParcel(address: address(1))
        let store = store
        let newAddress = address(2)
        let queue = makeQueue(onSleep: { try store.updateAddress(ofParcel: id, to: newAddress) })
        geocoder.responses = [.failure(.rateLimited)]

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(geocoder.requests == [address(1)])
        let saved = try parcel(id)
        #expect(saved.address == address(2))
        #expect(saved.geocodingStatus == .pending, "Nowy adres zgłasza do kolejki ekran edycji")
    }

    @Test("Usunięcie przesyłki podczas czekania przerywa ponawianie")
    func parcelDeletedDuringBackoff() async throws {
        let id = try store.addParcel(address: address(1))
        let store = store
        let queue = makeQueue(onSleep: { try store.deleteParcels([id]) })
        geocoder.responses = [.failure(.failed("offline"))]

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(geocoder.requests.count == 1)
        #expect(!queue.isRunning)
    }

    @Test("Limit i inne błędy mają osobne opóźnienia; baner limitu tylko przy limicie")
    func mixedErrorsBackoff() async throws {
        let queue = makeQueue()
        geocoder.responses = [.failure(.rateLimited), .failure(.failed("offline")), .failure(.rateLimited)]
        var waitingFlags: [Bool] = []
        geocoder.onGeocode = { _ in waitingFlags.append(queue.isWaitingForRateLimit) }
        let id = try store.addParcel(address: address(1))

        queue.enqueue(id)
        await queue.waitUntilIdle()

        #expect(sleeps.delays == [.seconds(2), .seconds(2), .seconds(4)])
        #expect(waitingFlags == [false, true, false, true])
        #expect(!queue.isWaitingForRateLimit)
        #expect(try parcel(id).geocodingStatus == .succeeded)
    }
}

/// Magazyn, który na żądanie rzuca błędem z wybranych metod, a poza tym
/// przekazuje wywołania do prawdziwego `SwiftDataParcelStore`.
@MainActor
final class FailingGeocodingStore: GeocodingStore {
    struct Failure: Error {}

    let base: SwiftDataParcelStore
    var failingAddressReads: Set<UUID> = []
    var failingRecords: Set<UUID> = []
    var failKnownCoordinate = false

    init(base: SwiftDataParcelStore) {
        self.base = base
    }

    func parcelIDs(withStatus status: GeocodingStatus) throws -> [UUID] {
        try base.parcelIDs(withStatus: status)
    }

    func address(ofParcel id: UUID) throws -> Address? {
        if failingAddressReads.contains(id) { throw Failure() }
        return try base.address(ofParcel: id)
    }

    func knownCoordinate(for address: Address) throws -> Coordinate? {
        if failKnownCoordinate { throw Failure() }
        return try base.knownCoordinate(for: address)
    }

    @discardableResult
    func recordGeocoding(_ outcome: GeocodingOutcome, ofParcel id: UUID, for address: Address) throws -> Bool {
        if failingRecords.contains(id) { throw Failure() }
        return try base.recordGeocoding(outcome, ofParcel: id, for: address)
    }
}
