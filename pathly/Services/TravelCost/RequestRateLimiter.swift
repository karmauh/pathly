import Foundation

/// Liczba zapytań wykonanych danego dnia.
nonisolated struct DailyUsage: Hashable, Codable, Sendable {
    /// Dzień w UTC w formacie `rrrr-mm-dd`.
    var day: String
    var count: Int
}

/// Trwały zapis dziennego licznika — przetrwa zamknięcie aplikacji.
nonisolated protocol DailyUsageStore: Sendable {
    func load() -> DailyUsage?
    func save(_ usage: DailyUsage)
}

/// Licznik w `UserDefaults`.
nonisolated struct UserDefaultsDailyUsageStore: DailyUsageStore {
    var key = "openRouteService.dailyUsage"

    func load() -> DailyUsage? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DailyUsage.self, from: data)
    }

    func save(_ usage: DailyUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Pilnuje limitów darmowego planu OpenRouteService po stronie aplikacji.
///
/// - **Na minutę:** przesuwane okno — gdy w ostatnich 60 s wykonano już
///   40 zapytań, kolejne czeka, aż najstarsze wypadnie z okna (zamiast dostać
///   błąd 429).
/// - **Na dzień:** licznik zapisany na dysku; po wyczerpaniu zgłasza
///   `TravelCostError.quotaExhausted`, a aplikacja przechodzi na przybliżenie.
///   Dzień liczymy w UTC.
actor RequestRateLimiter {
    nonisolated struct Limits: Sendable {
        var perMinute = 40
        var perDay = 500
        var window: TimeInterval = 60
    }

    private let limits: Limits
    private let usageStore: any DailyUsageStore
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    /// Chwile ostatnich zapytań w oknie minutowym.
    private var recent: [Date] = []

    init(
        limits: Limits = Limits(),
        usageStore: any DailyUsageStore = UserDefaultsDailyUsageStore(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.limits = limits
        self.usageStore = usageStore
        self.now = now
        self.sleep = sleep
    }

    /// Ile zapytań zostało na dziś.
    func remainingToday() -> Int {
        max(0, limits.perDay - usedToday(at: now()))
    }

    /// Czeka na wolne miejsce w limicie minutowym i rejestruje zapytanie.
    /// Wywołać tuż przed wysłaniem zapytania.
    func acquire() async throws {
        while true {
            let current = now()
            guard usedToday(at: current) < limits.perDay else {
                throw TravelCostError.quotaExhausted
            }
            recent.removeAll { current.timeIntervalSince($0) >= limits.window }
            if recent.count < limits.perMinute {
                recent.append(current)
                usageStore.save(DailyUsage(day: Self.dayKey(current), count: usedToday(at: current) + 1))
                return
            }
            // Czekamy, aż najstarsze zapytanie wypadnie z okna. Po wybudzeniu
            // sprawdzamy wszystko od nowa — inne zadanie mogło zająć miejsce.
            let wait = limits.window - current.timeIntervalSince(recent[0])
            try await sleep(.milliseconds(Int((wait * 1000).rounded(.up))))
        }
    }

    private func usedToday(at date: Date) -> Int {
        guard let usage = usageStore.load(), usage.day == Self.dayKey(date) else { return 0 }
        return usage.count
    }

    static func dayKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
