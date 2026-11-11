import Testing
@testable import pathly

@Suite("Coordinate")
struct CoordinateTests {
    let warsaw = Coordinate(latitude: 52.2297, longitude: 21.0122)
    let krakow = Coordinate(latitude: 50.0647, longitude: 19.9450)

    @Test("Haversine: Warszawa–Kraków ≈ 252 km")
    func warsawToKrakow() {
        let distance = warsaw.distance(to: krakow)
        #expect(abs(distance - 252_000) < 2_000)
    }

    @Test("Odległość jest symetryczna, a do siebie samego równa zero")
    func symmetryAndZero() {
        #expect(abs(warsaw.distance(to: krakow) - krakow.distance(to: warsaw)) < 0.001)
        #expect(warsaw.distance(to: warsaw) == 0)
    }

    @Test("Jeden stopień szerokości ≈ 111,2 km")
    func oneDegreeOfLatitude() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 1, longitude: 0)
        #expect(abs(a.distance(to: b) - 111_195) < 10)
    }

    @Test("Walidacja zakresów", arguments: [
        (52.0, 21.0, true), (91.0, 0.0, false), (0.0, -181.0, false), (-90.0, 180.0, true),
    ])
    func validity(latitude: Double, longitude: Double, expected: Bool) {
        #expect(Coordinate(latitude: latitude, longitude: longitude).isValid == expected)
    }
}
