import Testing
@testable import pathly

@Suite("StreetLineParser")
struct StreetLineParserTests {
    @Test("Formaty numerów budynku i lokalu", arguments: [
        ("ul. Długa 12", "ul. Długa", "12", nil),
        ("Długa 12A", "Długa", "12A", nil),
        ("Długa 12 a", "Długa", "12A", nil),
        ("ul. Długa 12/4", "ul. Długa", "12", "4"),
        ("ul. Długa 12 / 4", "ul. Długa", "12", "4"),
        ("ul. Długa 12 m. 4", "ul. Długa", "12", "4"),
        ("ul. Długa 12 m 4", "ul. Długa", "12", "4"),
        ("Kwiatowa 7 lok. 3", "Kwiatowa", "7", "3"),
        ("Lipowa 3a/2b", "Lipowa", "3A", "2B"),
        ("al. Jana Pawła II 45A m. 12", "al. Jana Pawła II", "45A", "12"),
        ("ul. 3 Maja 5", "ul. 3 Maja", "5", nil),
        ("Długa nr 12", "Długa", "12", nil),
        ("ul. Długa 12,", "ul. Długa", "12", nil),
        ("Wólka Kosowska 7", "Wólka Kosowska", "7", nil),
    ] as [(String, String, String, String?)])
    func parses(line: String, street: String, building: String, apartment: String?) throws {
        let parts = try #require(StreetLineParser.parse(line))
        #expect(parts == StreetParts(street: street, buildingNumber: building, apartmentNumber: apartment))
    }

    @Test("Linie bez numeru nie są ulicą", arguments: [
        "Jan Kowalski",
        "Sklep Internetowy Testowy Sp. z o.o.",
        "12",
    ])
    func rejects(line: String) {
        #expect(StreetLineParser.parse(line) == nil)
    }

    @Test("Prefiks ulicy")
    func streetPrefix() {
        #expect(StreetLineParser.hasStreetPrefix("UL. Długa"))
        #expect(StreetLineParser.hasStreetPrefix("os. Słoneczne"))
        #expect(!StreetLineParser.hasStreetPrefix("Ulrich Nowak"))
    }
}
