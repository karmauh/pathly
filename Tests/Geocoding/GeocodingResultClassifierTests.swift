import Testing
@testable import pathly

@Suite("GeocodingResultClassifier")
struct GeocodingResultClassifierTests {
    let warsawAddress = Address(street: "ul. Marszałkowska", buildingNumber: "10", postalCode: "00-590", city: "Warszawa")

    private func candidate(
        _ latitude: Double, _ longitude: Double,
        city: String? = "Warszawa", postalCode: String? = "00-590", label: String = ""
    ) -> GeocodingCandidate {
        GeocodingCandidate(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            label: label, city: city, postalCode: postalCode
        )
    }

    @Test("Brak kandydatów to brak wyniku")
    func empty() {
        #expect(GeocodingResultClassifier.classify([], for: warsawAddress) == .notFound)
    }

    @Test("Bliscy kandydaci (ten sam budynek) dają wynik jednoznaczny")
    func nearbyCandidates() {
        let first = candidate(52.2155, 21.0207)
        let result = GeocodingResultClassifier.classify([first, candidate(52.2157, 21.0210)], for: warsawAddress)
        #expect(result == .found(first))
    }

    @Test("Odlegli pasujący kandydaci dają wynik niejednoznaczny")
    func distantCandidates() {
        let candidates = [candidate(52.2155, 21.0207), candidate(52.2900, 20.9300)]
        #expect(GeocodingResultClassifier.classify(candidates, for: warsawAddress) == .ambiguous(candidates))
    }

    @Test("Miasto z łącznikiem pasuje do nazwy ze spacją mimo innego kodu (realny przypadek z MapKit)")
    func hyphenatedCityMatchesDespiteSpecificPostalCode() {
        // Etykieta: „43-300 Bielsko Biała” (ogólny kod miasta, łącznik zgubiony),
        // MapKit: „Szczęśliwa, 43-318 Bielsko-Biała, Polska”.
        let found = candidate(49.82, 19.04, city: "Bielsko-Biała", postalCode: "43-318", label: "Szczęśliwa, 43-318 Bielsko-Biała, Polska")
        let address = Address(street: "Szczęśliwa", buildingNumber: "137", postalCode: "43-300", city: "Bielsko Biała")
        #expect(GeocodingResultClassifier.classify([found], for: address) == .found(found))
    }

    @Test("Porównanie nazw ignoruje wielkość liter, znaki diakrytyczne, łączniki i nadmiarowe spacje")
    func comparableNames() {
        #expect(GeocodingResultClassifier.comparable("Bielsko-Biała") == GeocodingResultClassifier.comparable(" bielsko  biala "))
        #expect(GeocodingResultClassifier.comparable("Kędzierzyn–Koźle") == "kedzierzyn kozle")
        #expect(GeocodingResultClassifier.comparable("Łódź") == GeocodingResultClassifier.comparable("Lodz"))
        #expect(GeocodingResultClassifier.comparable("Kraków") != GeocodingResultClassifier.comparable("Krakówek"))
    }

    @Test("Przybliżony wynik z innej miejscowości jest odrzucany (realny przypadek z MapKit)")
    func rejectsFuzzyMatchFromAnotherTown() {
        let fuzzy = candidate(51.7838, 18.062, city: "Blizanów", postalCode: "62-800", label: "Warszówka 1, 62-800 Blizanów, Polska")
        let address = Address(street: "pl. Defilad", buildingNumber: "1", postalCode: "00-901", city: "Warszawa")
        #expect(GeocodingResultClassifier.classify([fuzzy], for: address) == .notFound)
    }

    @Test("Inny kod pocztowy w tej samej miejscowości jest akceptowany")
    func acceptsDifferentPostalCodeInSameCity() {
        let krakow = candidate(50.0621, 19.9394, city: "Kraków", postalCode: "31-043")
        let address = Address(street: "ul. Floriańska", buildingNumber: "1", postalCode: "31-019", city: "kraków")
        #expect(GeocodingResultClassifier.classify([krakow], for: address) == .found(krakow))
    }

    @Test("Wieś zwrócona z nazwą gminy pasuje po kodzie pocztowym lub pełnym adresie")
    func villageReturnedWithMunicipality() {
        let address = Address(street: "", buildingNumber: "7", postalCode: "05-532", city: "Wólka Kosowska")
        let byPostalCode = candidate(52.03, 20.95, city: "Lesznowola", postalCode: "05-532")
        let byLabel = candidate(52.03, 20.95, city: "Lesznowola", postalCode: nil, label: "Wolka Kosowska 7, Lesznowola")
        #expect(GeocodingResultClassifier.matches(byPostalCode, address))
        #expect(GeocodingResultClassifier.matches(byLabel, address))
    }

    @Test("Niepasujący kandydaci nie wpływają na niejednoznaczność")
    func nonMatchingCandidatesIgnored() {
        let good = candidate(52.2155, 21.0207)
        let elsewhere = candidate(51.7838, 18.062, city: "Blizanów", postalCode: "62-800")
        #expect(GeocodingResultClassifier.classify([good, elsewhere], for: warsawAddress) == .found(good))
    }
}
