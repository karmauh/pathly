import Foundation
import Testing
@testable import pathly

@MainActor
@Suite("Nawigacja zewnętrzna")
struct NavigationLauncherTests {
    let stop = Coordinate(latitude: 50.061_43, longitude: 19.936_58)

    @Test("Mapy Apple — trasa samochodem do punktu")
    func appleMaps() {
        let url = NavigationURLBuilder.appURL(for: .appleMaps, destination: stop)
        #expect(url.absoluteString == "https://maps.apple.com/?daddr=50.061430,19.936580&dirflg=d")
    }

    @Test("Mapy Google — aplikacja, a bez niej przeglądarka")
    func googleMaps() {
        let installed = NavigationLauncher(canOpen: { _ in true }, open: { _ in })
        #expect(installed.url(for: .googleMaps, destination: stop).absoluteString
                == "comgooglemaps://?daddr=50.061430,19.936580&directionsmode=driving")

        let missing = NavigationLauncher(canOpen: { _ in false }, open: { _ in })
        #expect(missing.url(for: .googleMaps, destination: stop).absoluteString
                == "https://www.google.com/maps/dir/?api=1&destination=50.061430,19.936580&travelmode=driving")
        #expect(missing.url(for: .appleMaps, destination: stop).host() == "maps.apple.com",
                "Mapy Apple nie zależą od canOpenURL")
    }

    @Test("Kropka dziesiętna i długość ujemna niezależnie od regionu")
    func coordinateFormat() {
        #expect(NavigationURLBuilder.coordinateText(Coordinate(latitude: -33.5, longitude: -70.123_456_7)) == "-33.500000,-70.123457")
    }

    @Test("Otwiera wyliczony adres")
    func opens() {
        var opened: [URL] = []
        let launcher = NavigationLauncher(canOpen: { _ in true }, open: { opened.append($0) })
        launcher.navigate(to: stop, using: .appleMaps)
        #expect(opened == [NavigationURLBuilder.appURL(for: .appleMaps, destination: stop)])
    }
}
