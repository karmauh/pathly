import Foundation
import Testing
@testable import pathly

@Suite("RequestRateLimiter")
struct RequestRateLimiterTests {
    let clock = FakeClock()
    let usage = InMemoryDailyUsageStore()

    @Test("40 zapytań w minucie bez czekania, 41. czeka na zwolnienie okna")
    func perMinute() async throws {
        let limiter = RequestRateLimiter.test(clock: clock, usage: usage)
        for _ in 0..<40 {
            try await limiter.acquire()
            clock.advance(by: 0.5)
        }
        #expect(clock.sleeps.isEmpty)

        try await limiter.acquire()
        // Pierwsze zapytanie było 20 s temu → czekamy 40 s.
        #expect(clock.sleeps == [.seconds(40)])
        #expect(usage.current?.count == 41)
    }

    @Test("Po wyczerpaniu dziennego limitu — quotaExhausted")
    func dailyLimit() async throws {
        var limits = RequestRateLimiter.Limits()
        limits.perDay = 3
        let limiter = RequestRateLimiter.test(clock: clock, usage: usage, limits: limits)

        for _ in 0..<3 { try await limiter.acquire() }

        #expect(await limiter.remainingToday() == 0)
        await #expect(throws: TravelCostError.quotaExhausted) { try await limiter.acquire() }
    }

    @Test("Licznik dzienny przetrwa ponowne uruchomienie i zeruje się następnego dnia")
    func persistsAndResets() async throws {
        var limits = RequestRateLimiter.Limits()
        limits.perDay = 5
        try await RequestRateLimiter.test(clock: clock, usage: usage, limits: limits).acquire()
        try await RequestRateLimiter.test(clock: clock, usage: usage, limits: limits).acquire()

        let restarted = RequestRateLimiter.test(clock: clock, usage: usage, limits: limits)
        #expect(await restarted.remainingToday() == 3)

        clock.advance(by: 24 * 60 * 60)
        #expect(await restarted.remainingToday() == 5)
    }

    @Test("Dzień liczony w UTC")
    func dayKey() {
        #expect(RequestRateLimiter.dayKey(Date(timeIntervalSince1970: 0)) == "1970-01-01")
        #expect(RequestRateLimiter.dayKey(Date(timeIntervalSince1970: 86_399)) == "1970-01-01")
        #expect(RequestRateLimiter.dayKey(Date(timeIntervalSince1970: 86_400)) == "1970-01-02")
    }
}
