import Foundation
import Testing
@testable import pathly

@MainActor
@Suite("Nawigacja zewnętrzna")
struct NavigationLauncherTests {
    let stop = Coordinate(latitude: 50.061_43, longitude: 19.936_58)
    let base = Coordinate(latitude: 50.0, longitude: 19.9)

    /// Trasa z `count` przystankami w kolejności, z podanymi statusami pierwszych.
    private func route(_ count: Int, completed: Int = 0) -> (RouteProgress, [UUID: Coordinate]) {
        let ids = (0..<count).map { _ in UUID() }
        var statuses = Dictionary(uniqueKeysWithValues: ids.map { ($0, DeliveryStatus.pending) })
        for id in ids.prefix(completed) { statuses[id] = .delivered }
        let coordinates = Dictionary(uniqueKeysWithValues: ids.enumerated().map {
            ($0.element, Coordinate(latitude: 50 + Double($0.offset) * 0.01, longitude: 20))
        })
        return (RouteProgress(stopOrder: ids, statuses: statuses), coordinates)
    }

    @Test("Mapy Apple — trasa samochodem do punktu")
    func appleMaps() {
        let url = NavigationURLBuilder.url(for: .appleMaps, destination: stop)
        #expect(url.absoluteString == "https://maps.apple.com/?daddr=50.061430,19.936580&dirflg=d")
    }

    @Test("Mapy Google — jeden punkt")
    func googleSingle() {
        #expect(NavigationURLBuilder.url(for: .googleMaps, destination: stop).absoluteString
                == "https://www.google.com/maps/dir/?api=1&destination=50.061430,19.936580&travelmode=driving")
    }

    @Test("Mapy Google — przystanki pośrednie w kolejności, baza jako cel")
    func googleBatch() throws {
        let batch = NavigationBatch(
            parcelIDs: [UUID(), UUID()],
            stops: [Coordinate(latitude: 50.1, longitude: 20), Coordinate(latitude: 50.2, longitude: 20)],
            base: base
        )
        let components = try #require(URLComponents(url: NavigationURLBuilder.googleRouteURL(for: batch), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.host == "www.google.com")
        #expect(query["destination"] == "50.000000,19.900000")
        #expect(query["waypoints"] == "50.100000,20.000000|50.200000,20.000000")
        #expect(query["travelmode"] == "driving")
    }

    @Test("Partia: najwyżej 9 kolejnych niezrealizowanych przystanków, bez bazy")
    func batchOfNine() throws {
        let (progress, coordinates) = route(20, completed: 3)
        let batch = try #require(NavigationBatch.next(in: progress, coordinates: coordinates, base: base))

        #expect(batch.parcelIDs == progress.entries[3..<12].map(\.parcelID))
        #expect(!batch.returnsToBase)
    }

    @Test("Ostatnia partia kończy się w bazie, gdy zmieści się razem z nią")
    func lastBatchReturnsToBase() throws {
        let (progress, coordinates) = route(10, completed: 2)
        let batch = try #require(NavigationBatch.next(in: progress, coordinates: coordinates, base: base))
        #expect(batch.stops.count == 8)
        #expect(batch.base == base)

        // 9 pozostałych + baza to za dużo — baza w następnej partii.
        let (nine, nineCoordinates) = route(9)
        #expect(NavigationBatch.next(in: nine, coordinates: nineCoordinates, base: base)?.returnsToBase == false)
    }

    @Test("Pomija niedoręczone, a po zakończeniu trasy nie ma partii")
    func skipsCompleted() {
        let (progress, coordinates) = route(3)
        let statuses = [progress.entries[0].parcelID: DeliveryStatus.notDelivered,
                        progress.entries[1].parcelID: .pending,
                        progress.entries[2].parcelID: .delivered]
        let mixed = RouteProgress(stopOrder: progress.entries.map(\.parcelID), statuses: statuses)
        #expect(NavigationBatch.next(in: mixed, coordinates: coordinates, base: nil)?.parcelIDs == [progress.entries[1].parcelID])

        let (done, doneCoordinates) = route(2, completed: 2)
        #expect(NavigationBatch.next(in: done, coordinates: doneCoordinates, base: base) == nil)
    }

    @Test("Mapy Apple dostają tylko pierwszy przystanek partii, Mapy Google — całą")
    func launcherUsesBatch() throws {
        let (progress, coordinates) = route(4)
        let batch = try #require(NavigationBatch.next(in: progress, coordinates: coordinates, base: base))
        var opened: [URL] = []
        let launcher = NavigationLauncher(open: { opened.append($0) })

        launcher.navigate(through: batch, using: .appleMaps)
        launcher.navigate(through: batch, using: .googleMaps)

        #expect(opened == [
            NavigationURLBuilder.url(for: .appleMaps, destination: batch.stops[0]),
            NavigationURLBuilder.googleRouteURL(for: batch),
        ])
    }

    @Test("Opis partii z odmianą liczby przystanków")
    func descriptions() {
        #expect(NavigationBatch.stopCountText(1) == "ostatni przystanek")
        #expect(NavigationBatch.stopCountText(3) == "3 kolejne przystanki")
        #expect(NavigationBatch.stopCountText(9) == "9 kolejnych przystanków")
    }

    @Test("Kropka dziesiętna i długość ujemna niezależnie od regionu")
    func coordinateFormat() {
        #expect(NavigationURLBuilder.coordinateText(Coordinate(latitude: -33.5, longitude: -70.123_456_7)) == "-33.500000,-70.123457")
    }
}
