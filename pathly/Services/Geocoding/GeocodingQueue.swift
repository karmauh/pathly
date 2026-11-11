import Foundation
import Observation

/// Kolejka geokodowania przesyłek.
///
/// - **Sekwencyjnie:** jedno zadanie w tle obsługuje przesyłki po kolei, więc do
///   Apple nigdy nie idzie kilka zapytań naraz.
/// - **Od razu po zatwierdzeniu:** przesyłka trafia tu przy zapisie, a nie przy
///   wyliczaniu trasy — zapytania rozkładają się w czasie.
/// - **Bez zbędnych zapytań:** adres, dla którego znamy już współrzędne (ta sama
///   przesyłka albo inna paczka pod ten sam adres), nie jest geokodowany ponownie.
/// - **Ponawianie:** po błędzie limitu czeka coraz dłużej (2, 4, 8… s); po
///   wyczerpaniu prób przesyłka dostaje status `failed` i można ją ponowić ręcznie.
@Observable
final class GeocodingQueue: GeocodingScheduling {
    /// Zasady ponawiania po błędach technicznych.
    struct RetryPolicy {
        /// Ile razy ponowić po przekroczeniu limitu zapytań.
        var rateLimitRetries = 5
        /// Ile razy ponowić po innym błędzie (np. brak sieci).
        var failureRetries = 2
        /// Opóźnienie pierwszego ponowienia; każde kolejne jest dwa razy dłuższe.
        var initialDelay: Duration = .seconds(2)
    }

    /// Przesyłki obsłużone w bieżącej serii (zeruje się, gdy kolejka się opróżni).
    private(set) var completed = 0
    /// Wszystkie przesyłki bieżącej serii.
    private(set) var total = 0
    /// Kolejka czeka po błędzie limitu zapytań.
    private(set) var isWaitingForRateLimit = false

    var isRunning: Bool { worker != nil }

    private var waiting: [UUID] = []
    private var current: UUID?
    private var worker: Task<Void, Never>?

    private let geocoder: any Geocoder
    private let store: any GeocodingStore
    private let policy: RetryPolicy
    private let sleep: (Duration) async throws -> Void

    init(
        geocoder: any Geocoder,
        store: any GeocodingStore,
        policy: RetryPolicy = RetryPolicy(),
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.geocoder = geocoder
        self.store = store
        self.policy = policy
        self.sleep = sleep
    }

    /// Czy przesyłka czeka w kolejce albo jest właśnie geokodowana.
    func isScheduled(_ parcelID: UUID) -> Bool {
        current == parcelID || waiting.contains(parcelID)
    }

    /// Dodaje przesyłkę na koniec kolejki.
    ///
    /// Przesyłka właśnie geokodowana może trafić tu ponownie — to znaczy, że
    /// kurier zmienił adres w trakcie zapytania i stary wynik zostanie odrzucony.
    func enqueue(_ parcelID: UUID) {
        guard !waiting.contains(parcelID) else { return }
        waiting.append(parcelID)
        total += 1
        startIfNeeded()
    }

    /// Podejmuje przesyłki, których geokodowanie przerwało zamknięcie aplikacji.
    func resumePending() {
        enqueueAll(withStatus: .pending)
    }

    /// Ponawia przesyłki, których nie udało się geokodować z powodów technicznych.
    func retryFailed() {
        enqueueAll(withStatus: .failed)
    }

    /// Czeka, aż kolejka się opróżni (używane w testach).
    func waitUntilIdle() async {
        await worker?.value
    }

    // MARK: Przetwarzanie

    private func enqueueAll(withStatus status: GeocodingStatus) {
        guard let ids = try? store.parcelIDs(withStatus: status) else { return }
        ids.forEach(enqueue)
    }

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    private func drain() async {
        while !waiting.isEmpty {
            let id = waiting.removeFirst()
            current = id
            await process(id)
            current = nil
            completed += 1
        }
        worker = nil
        completed = 0
        total = 0
    }

    private func process(_ id: UUID) async {
        // Przesyłka mogła zostać usunięta, zanim przyszła jej kolej.
        guard let address = try? store.address(ofParcel: id) else { return }

        let outcome: GeocodingOutcome
        if let known = try? store.knownCoordinate(for: address) {
            outcome = .located(known)
        } else {
            outcome = await geocodeWithRetry(address)
        }
        // Wynik dla nieaktualnego adresu jest odrzucany przez magazyn.
        _ = try? store.recordGeocoding(outcome, ofParcel: id, for: address)
    }

    private func geocodeWithRetry(_ address: Address) async -> GeocodingOutcome {
        var rateLimitRetries = 0
        var failureRetries = 0
        var delay = policy.initialDelay
        defer { isWaitingForRateLimit = false }

        while true {
            do {
                return GeocodingOutcome(try await geocoder.geocode(address))
            } catch GeocodingError.rateLimited {
                guard rateLimitRetries < policy.rateLimitRetries else { return .failed }
                rateLimitRetries += 1
                isWaitingForRateLimit = true
            } catch {
                guard failureRetries < policy.failureRetries else { return .failed }
                failureRetries += 1
            }
            do {
                try await sleep(delay)
            } catch {
                return .failed  // anulowane czekanie
            }
            delay *= 2
        }
    }
}
