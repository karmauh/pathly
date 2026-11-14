import Foundation
import Observation
import os

/// Kolejka geokodowania przesyłek.
///
/// - **Sekwencyjnie:** jedno zadanie w tle obsługuje przesyłki po kolei, więc do
///   Apple nigdy nie idzie kilka zapytań naraz.
/// - **Od razu po zatwierdzeniu:** przesyłka trafia tu przy zapisie, a nie przy
///   wyliczaniu trasy — zapytania rozkładają się w czasie.
/// - **Bez zbędnych zapytań:** adres, dla którego znamy już współrzędne (ta sama
///   przesyłka albo inna paczka pod ten sam adres), nie jest geokodowany ponownie.
/// - **Ponawianie:** po błędzie czeka coraz dłużej (2, 4, 8… s), osobno dla limitu
///   zapytań i dla innych błędów; po wyczerpaniu prób przesyłka dostaje status
///   `failed` i można ją ponowić ręcznie.
/// - **Wyczerpany limit zatrzymuje serię:** pozostałe przesyłki od razu dostają
///   `failed` bez zapytań, zamiast każda z osobna czekać na limit od nowa.
/// - **Anulowanie nie jest błędem:** przerwane zadanie niczego nie zapisuje, więc
///   przesyłka zostaje `pending` i `resumePending` podejmie ją później.
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

        /// Opóźnienie przed ponowieniem numer `retry` (od zera) danego rodzaju błędu.
        func delay(beforeRetry retry: Int) -> Duration {
            initialDelay * (1 << retry)
        }
    }

    /// Przesyłki obsłużone w bieżącej serii (także pominięte, np. usunięte);
    /// zeruje się, gdy kolejka się opróżni.
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

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "pathly", category: "geocoding")

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

    /// Jak skończyła się obsługa jednej przesyłki.
    private enum Attempt {
        /// Wynik do zapisania.
        case outcome(GeocodingOutcome)
        /// Limit zapytań nie minął mimo wszystkich ponowień.
        case rateLimitExhausted
        /// Zadanie anulowane albo adres zmienił się w trakcie czekania — nic nie zapisujemy.
        case abandoned
    }

    private func enqueueAll(withStatus status: GeocodingStatus) {
        do {
            try store.parcelIDs(withStatus: status).forEach(enqueue)
        } catch {
            Self.logger.error("Nie udało się pobrać przesyłek o statusie \(String(describing: status), privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    private func drain() async {
        var rateLimitExhausted = false
        while !waiting.isEmpty, !Task.isCancelled {
            let id = waiting.removeFirst()
            current = id
            if case .rateLimitExhausted = await process(id, requestAllowed: !rateLimitExhausted) {
                rateLimitExhausted = true
            }
            current = nil
            completed += 1
        }
        // Po anulowaniu pozostałe przesyłki zostają `pending` w magazynie.
        waiting.removeAll()
        worker = nil
        completed = 0
        total = 0
    }

    /// Geokoduje jedną przesyłkę i zapisuje wynik.
    ///
    /// - Parameter requestAllowed: `false` po wyczerpaniu limitu — przesyłka bez
    ///   znanych współrzędnych dostaje wtedy `failed` bez zapytania do Apple.
    private func process(_ id: UUID, requestAllowed: Bool) async -> Attempt {
        let address: Address
        do {
            // `nil` — przesyłka została usunięta, zanim przyszła jej kolej.
            guard let found = try store.address(ofParcel: id) else { return .abandoned }
            address = found
        } catch {
            log(error, "Nie udało się odczytać adresu", parcel: id)
            return .abandoned
        }

        let attempt: Attempt
        if let known = knownCoordinate(for: address) {
            attempt = .outcome(.located(known))
        } else if requestAllowed {
            attempt = await geocodeWithRetry(address, ofParcel: id)
        } else {
            attempt = .outcome(.failed)
        }

        switch attempt {
        case .outcome(let outcome):
            record(outcome, ofParcel: id, for: address)
        case .rateLimitExhausted:
            record(.failed, ofParcel: id, for: address)
        case .abandoned:
            break
        }
        return attempt
    }

    private func geocodeWithRetry(_ address: Address, ofParcel id: UUID) async -> Attempt {
        var rateLimitRetries = 0
        var failureRetries = 0
        defer { isWaitingForRateLimit = false }

        while true {
            let delay: Duration
            do {
                return .outcome(GeocodingOutcome(try await geocoder.geocode(address)))
            } catch is CancellationError {
                return .abandoned
            } catch where Task.isCancelled {
                return .abandoned
            } catch GeocodingError.rateLimited {
                guard rateLimitRetries < policy.rateLimitRetries else { return .rateLimitExhausted }
                delay = policy.delay(beforeRetry: rateLimitRetries)
                rateLimitRetries += 1
                isWaitingForRateLimit = true
            } catch {
                guard failureRetries < policy.failureRetries else { return .outcome(.failed) }
                delay = policy.delay(beforeRetry: failureRetries)
                failureRetries += 1
                isWaitingForRateLimit = false
            }

            do {
                try await sleep(delay)
            } catch {
                return .abandoned  // anulowane czekanie
            }
            // Podczas czekania kurier mógł zmienić adres albo usunąć przesyłkę —
            // nie marnujemy wtedy zapytań na nieaktualny adres.
            guard isStillCurrent(address, ofParcel: id) else { return .abandoned }
        }
    }

    // MARK: Magazyn

    private func knownCoordinate(for address: Address) -> Coordinate? {
        do {
            return try store.knownCoordinate(for: address)
        } catch {
            Self.logger.error("Nie udało się sprawdzić znanych współrzędnych: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func isStillCurrent(_ address: Address, ofParcel id: UUID) -> Bool {
        do {
            return try store.address(ofParcel: id) == address
        } catch {
            // Nie wiemy, więc ponawiamy; nieaktualny wynik i tak odrzuci zapis.
            log(error, "Nie udało się odczytać adresu", parcel: id)
            return true
        }
    }

    private func record(_ outcome: GeocodingOutcome, ofParcel id: UUID, for address: Address) {
        do {
            // Wynik dla nieaktualnego adresu jest odrzucany przez magazyn.
            try store.recordGeocoding(outcome, ofParcel: id, for: address)
        } catch {
            // Przesyłka zostaje `pending` — `resumePending` podejmie ją przy starcie.
            log(error, "Nie udało się zapisać wyniku geokodowania", parcel: id)
        }
    }

    private func log(_ error: any Error, _ message: String, parcel id: UUID) {
        Self.logger.error("\(message, privacy: .public) (przesyłka \(id.uuidString, privacy: .public)): \(error.localizedDescription, privacy: .public)")
    }
}
