import Testing
@testable import pathly

@Suite("LineClassifier")
struct LineClassifierTests {
    @Test("Kotwice odbiorcy", arguments: [
        ("Odbiorca", ""),
        ("ODBIORCA:", ""),
        ("Odbiorca: Jan Kowalski", "Jan Kowalski"),
        ("Adres doręczenia:", ""),
        ("Doręczyć do: Anna Nowak", "Anna Nowak"),
        ("Do: Piotr Wiśniewski", "Piotr Wiśniewski"),
        ("Ship to", ""),
        ("DELIVER TO:", ""),
        ("Recipient: ACME", "ACME"),
    ])
    func recipientAnchors(line: String, remainder: String) {
        #expect(LineClassifier.classify(line) == .anchor(.recipient, remainder: remainder))
    }

    @Test("Kotwice nadawcy", arguments: ["Nadawca", "Od:", "From: Shop", "SENDER", "Shipper:", "Adres zwrotny"])
    func senderAnchors(line: String) {
        guard case .anchor(.sender, _) = LineClassifier.classify(line) else {
            Issue.record("\(line) nie rozpoznano jako kotwicy nadawcy")
            return
        }
    }

    @Test("Słowa zaczynające się jak kotwice nie są kotwicami", arguments: ["Dobra 5", "Odrzańska 3", "Fromborska 2", "Do zapłaty"])
    func notAnchors(line: String) {
        if case .anchor = LineClassifier.classify(line) {
            Issue.record("\(line) błędnie uznano za kotwicę")
        }
    }

    @Test("Szum", arguments: [
        "Waga: 2,5 kg",
        "12 kg",
        "tel. 600 100 200",
        "+48 600 100 200",
        "600100200",
        "6200 1234 5678 9012",
        "Nr przesyłki: 620012345678",
        "Uwagi: zostawić u sąsiada",
        "Data nadania: 2026-11-11",
        "Pobranie: 120,00 zł",
    ])
    func noise(line: String) {
        #expect(LineClassifier.classify(line) == .noise)
    }

    @Test("Kod z miejscowością, ulica i inne")
    func otherKinds() {
        guard case .postalCity = LineClassifier.classify("31-019 Kraków") else {
            Issue.record("Oczekiwano kodu z miejscowością")
            return
        }
        #expect(LineClassifier.classify("ul. Długa 12/4") == .street(StreetParts(street: "ul. Długa", buildingNumber: "12", apartmentNumber: "4")))
        #expect(LineClassifier.classify("ul. Długa") == .street(StreetParts(street: "ul. Długa", buildingNumber: "", apartmentNumber: nil)))
        #expect(LineClassifier.classify("Jan Kowalski") == .other)
        #expect(LineClassifier.classify("Telimena Nowak") == .other)
    }
}
