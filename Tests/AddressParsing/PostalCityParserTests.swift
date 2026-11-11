import Testing
@testable import pathly

@Suite("PostalCityParser")
struct PostalCityParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let line: String
        let postalCode: String
        let city: String
        var precedingText = ""
        var corrected = false
        var testDescription: String { line }
    }

    @Test("Rozpoznaje kod i miejscowość", arguments: [
        Case(line: "00-950 Warszawa", postalCode: "00-950", city: "Warszawa"),
        Case(line: "Kraków 31-019", postalCode: "31-019", city: "Kraków"),
        Case(line: "00-950 Warszawa, Polska", postalCode: "00-950", city: "Warszawa"),
        Case(line: "PL-31-019 Kraków", postalCode: "31-019", city: "Kraków"),
        Case(line: "PL-81225 Gdynia", postalCode: "81-225", city: "Gdynia"),
        Case(line: "00950 Warszawa", postalCode: "00-950", city: "Warszawa"),
        Case(line: "00 - 950 Warszawa", postalCode: "00-950", city: "Warszawa"),
        Case(line: "0O-95O Warszawa", postalCode: "00-950", city: "Warszawa", corrected: true),
        Case(line: "3l-O19 Kraków", postalCode: "31-019", city: "Kraków", corrected: true),
        Case(line: "ul. Lipowa 3, 20-001 Lublin", postalCode: "20-001", city: "Lublin", precedingText: "ul. Lipowa 3"),
    ])
    func parses(testCase: Case) throws {
        let match = try #require(PostalCityParser.parse(testCase.line))
        #expect(match.postalCode == testCase.postalCode)
        #expect(match.city == testCase.city)
        #expect(match.precedingText == testCase.precedingText)
        #expect(match.wasCorrected == testCase.corrected)
    }

    @Test("Nie myli innych liczb z kodem pocztowym", arguments: [
        "tel. 600 100 200",
        "500-100-200",
        "6200 1234 5678 9012",
        "Data: 2026-11-11",
        "00-950",
        "Sklep BOSSO 12",
        "Waga 12,50 kg",
    ])
    func rejects(line: String) {
        #expect(PostalCityParser.parse(line) == nil)
    }
}
