import Foundation

/// Zaburzenia trasy dla kolejnych startów przeszukiwania lokalnego (multi-start).
nonisolated enum Perturbation {
    /// Ruch „double bridge”: przystanki `A B C D` → `A C B D`.
    ///
    /// Zamienia miejscami dwa sąsiednie fragmenty bez odwracania żadnego z nich,
    /// więc dobrze pasuje do macierzy asymetrycznej. Takiej zmiany nie da się
    /// łatwo cofnąć pojedynczym ruchem Or-opt ani 2-opt, dlatego wyprowadza
    /// przeszukiwanie z lokalnego minimum. Wymaga co najmniej 2 przystanków.
    static func doubleBridge(_ tour: [Int], using generator: inout some RandomNumberGenerator) -> [Int] {
        let stops = TourCost.stops(of: tour)
        guard stops.count >= 2 else { return tour }

        // Trzy różne cięcia z 0…n wyznaczają niepuste B i C (A i D mogą być puste).
        var cuts = Set<Int>()
        while cuts.count < 3 {
            cuts.insert(Int.random(in: 0...stops.count, using: &generator))
        }
        let sorted = cuts.sorted()
        let (first, second, third) = (sorted[0], sorted[1], sorted[2])

        let reordered = stops[..<first] + stops[second..<third] + stops[first..<second] + stops[third...]
        return TourCost.closedTour(stops: Array(reordered))
    }
}

/// Prosty, deterministyczny generator liczb losowych (SplitMix64).
///
/// Stałe ziarno daje powtarzalne trasy i powtarzalne testy; `SystemRandomNumberGenerator`
/// nie pozwala ustawić ziarna.
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
