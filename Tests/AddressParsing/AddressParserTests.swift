import Testing
@testable import pathly

@Suite("AddressParser")
struct AddressParserTests {
    let parser = AddressParser()

    @Test("Zestaw fikcyjnych etykiet", arguments: LabelFixture.all)
    func fixture(_ fixture: LabelFixture) {
        let result = parser.parse(fixture.lines)
        switch (fixture.expected, result) {
        case (.recipient(let expected), .recipient(let parsed)):
            #expect(parsed.address == expected)
        case (.candidates(let expected), .candidates(let parsed)):
            #expect(parsed.map(\.address) == expected)
        case (.notFound, .notFound):
            break
        default:
            Issue.record("Oczekiwano \(fixture.expected), otrzymano \(result)")
        }
    }

    @Test("Adres nadawcy nigdy nie jest wynikiem")
    func senderIsNeverReturned() {
        for fixture in LabelFixture.all {
            guard case .recipient(let parsed) = parser.parse(fixture.lines) else { continue }
            #expect(!["Magazynowa", "Fabryczna", "Przemysłowa", "Portowa", "Spokojna", "Handlowa"]
                .contains { parsed.address.street.contains($0) }, "\(fixture.name)")
        }
    }

    @Test("Poprawiony kod pocztowy jest oznaczony i obniża pewność")
    func correctedPostalCodeWarning() throws {
        guard case .recipient(let corrected) = parser.parse(LabelFixture.ocrErrorsInPostalCode.lines),
              case .recipient(let clean) = parser.parse(LabelFixture.singleColumn.lines)
        else {
            Issue.record("Oczekiwano adresów odbiorcy")
            return
        }
        #expect(corrected.warnings.contains(.postalCodeCorrected))
        #expect(!clean.warnings.contains(.postalCodeCorrected))
        #expect(corrected.confidence < clean.confidence)
    }

    @Test("Adres bez kotwicy ma niższą pewność i ostrzeżenie")
    func unanchoredAddressConfidence() {
        guard case .recipient(let unanchored) = parser.parse(LabelFixture.noAnchorsSingleAddress.lines),
              case .recipient(let anchored) = parser.parse(LabelFixture.singleColumn.lines)
        else {
            Issue.record("Oczekiwano adresów odbiorcy")
            return
        }
        #expect(unanchored.warnings.contains(.recipientNotMarked))
        #expect(unanchored.confidence < anchored.confidence)
        #expect((0...1).contains(unanchored.confidence))
    }

    @Test("Brak numeru budynku daje ostrzeżenie")
    func missingBuildingNumber() {
        let lines = Label.column(x: 0.1, y: 0.1, ["Odbiorca:", "ul. Długa", "31-019 Kraków"])
        guard case .recipient(let parsed) = parser.parse(lines) else {
            Issue.record("Oczekiwano adresu odbiorcy")
            return
        }
        #expect(parsed.address.street == "ul. Długa")
        #expect(parsed.warnings.contains(.missingBuildingNumber))
    }

    @Test("Pusta etykieta lub sam szum")
    func emptyInput() {
        #expect(parser.parse([]) == .notFound)
        #expect(parser.parse(Label.column(x: 0.1, y: 0.1, ["6200 1234 5678 9012", "Waga: 3 kg"])) == .notFound)
    }

    @Test("Kolejność linii na wejściu nie zmienia wyniku")
    func inputOrderIndependent() {
        for fixture in LabelFixture.all {
            #expect(parser.parse(fixture.lines) == parser.parse(fixture.lines.reversed()), "\(fixture.name)")
        }
    }
}
