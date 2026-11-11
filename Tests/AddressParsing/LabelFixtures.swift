import Testing
@testable import pathly

/// Fikcyjne etykiety przewozowe (zanonimizowane, zmyślone dane) do testów parsera.
///
/// Układy naśladują typowe listy przewozowe: jedna i dwie kolumny, formularz
/// z etykietami po lewej, kotwice polskie i angielskie, tekst wielkimi literami,
/// błędy OCR w kodzie pocztowym oraz dużo szumu (kody kreskowe, wagi, telefony).
/// Współrzędne są znormalizowane 0–1, początek w lewym górnym rogu.
struct LabelFixture: Sendable, CustomTestStringConvertible {
    enum Expected: Sendable {
        case recipient(Address)
        case candidates([Address])
        case notFound
    }

    let name: String
    let lines: [RecognizedLine]
    let expected: Expected

    var testDescription: String { name }
}

/// Proste budowanie linii etykiety.
enum Label {
    static let lineHeight = 0.03
    static let lineSpacing = 0.01

    /// Pojedyncza linia; szerokość szacowana z długości tekstu.
    static func line(
        _ text: String, x: Double, y: Double,
        width: Double? = nil, height: Double = lineHeight, confidence: Double = 0.95
    ) -> RecognizedLine {
        RecognizedLine(
            text: text,
            box: TextBox(x: x, y: y, width: width ?? min(0.9, Double(text.count) * 0.011), height: height),
            confidence: confidence
        )
    }

    /// Kolumna linii wyrównanych do lewej, jedna pod drugą.
    static func column(
        x: Double, y: Double, height: Double = lineHeight, confidence: Double = 0.95, _ texts: [String]
    ) -> [RecognizedLine] {
        texts.enumerated().map { index, text in
            line(text, x: x, y: y + Double(index) * (height + lineSpacing), height: height, confidence: confidence)
        }
    }
}

extension LabelFixture {
    static let all: [LabelFixture] = [
        singleColumn, tightSingleColumn, twoColumns, englishAnchors, inlineAnchor,
        formWithLabelsOnLeft, noAnchorsSingleAddress, noAnchorsTwoAddresses, uppercase,
        ocrErrorsInPostalCode, ruralWithoutStreet, noisyLabel, senderOnly,
        addressInOneLine, countryPrefixWithoutDash,
    ]

    /// Nadawca u góry, odbiorca niżej, wyraźna przerwa między blokami.
    static let singleColumn = LabelFixture(
        name: "Jedna kolumna: nadawca nad odbiorcą",
        lines: Label.column(x: 0.05, y: 0.05, [
            "NADAWCA:", "Sklep Internetowy Testowy Sp. z o.o.", "ul. Magazynowa 5", "02-652 Warszawa",
        ]) + Label.column(x: 0.05, y: 0.35, [
            "ODBIORCA:", "Jan Kowalski", "ul. Długa 12/4", "31-019 Kraków", "tel. 600 100 200",
        ]) + Label.column(x: 0.05, y: 0.80, [
            "Waga: 2,5 kg", "Nr przesyłki: 620012345678901234",
        ]),
        expected: .recipient(Address(street: "ul. Długa", buildingNumber: "12", apartmentNumber: "4", postalCode: "31-019", city: "Kraków"))
    )

    /// Bez przerwy między nadawcą a odbiorcą — rozdziela je tylko kotwica.
    static let tightSingleColumn = LabelFixture(
        name: "Jedna kolumna bez przerw: podział przy kotwicy",
        lines: Label.column(x: 0.05, y: 0.05, [
            "Nadawca", "Hurtownia Przykładowa", "ul. Fabryczna 10", "02-001 Warszawa",
            "Odbiorca", "Anna Nowak", "ul. Ogrodowa 8 m. 2", "61-001 Poznań",
        ]),
        expected: .recipient(Address(street: "ul. Ogrodowa", buildingNumber: "8", apartmentNumber: "2", postalCode: "61-001", city: "Poznań"))
    )

    /// Nadawca w lewej kolumnie, odbiorca w prawej, nad nimi szeroki nagłówek.
    static let twoColumns = LabelFixture(
        name: "Dwie kolumny z nagłówkiem przewoźnika",
        lines: [Label.line("KURIER TESTOWY EXPRESS", x: 0.05, y: 0.02, width: 0.9)]
            + Label.column(x: 0.05, y: 0.10, ["Od:", "Firma Testowa S.A.", "ul. Przemysłowa 3", "60-001 Poznań"])
            + Label.column(x: 0.55, y: 0.10, ["Do:", "Katarzyna Wójcik", "al. Jana Pawła II 45A m. 12", "00-828 Warszawa"]),
        expected: .recipient(Address(street: "al. Jana Pawła II", buildingNumber: "45A", apartmentNumber: "12", postalCode: "00-828", city: "Warszawa"))
    )

    static let englishAnchors = LabelFixture(
        name: "Kotwice angielskie, ulica bez prefiksu",
        lines: Label.column(x: 0.05, y: 0.05, ["FROM:", "Test Shop Ltd", "Portowa 1", "81-001 Gdynia"])
            + Label.column(x: 0.05, y: 0.40, ["SHIP TO:", "Marek Zieliński", "Kwiatowa 7 lok. 3", "80-001 Gdańsk"]),
        expected: .recipient(Address(street: "Kwiatowa", buildingNumber: "7", apartmentNumber: "3", postalCode: "80-001", city: "Gdańsk"))
    )

    /// Kotwica w tej samej linii co nazwisko.
    static let inlineAnchor = LabelFixture(
        name: "Kotwica w jednej linii z nazwiskiem",
        lines: Label.column(x: 0.05, y: 0.05, ["Nadawca: Firma ABC", "ul. Spokojna 2", "30-001 Kraków"])
            + Label.column(x: 0.05, y: 0.40, ["Odbiorca: Piotr Wiśniewski", "ul. Ogrodowa 8", "61-001 Poznań"]),
        expected: .recipient(Address(street: "ul. Ogrodowa", buildingNumber: "8", postalCode: "61-001", city: "Poznań"))
    )

    /// Formularz: etykiety pól w lewej kolumnie, dane w prawej.
    static let formWithLabelsOnLeft = LabelFixture(
        name: "Formularz z etykietami po lewej",
        lines: [Label.line("Nadawca:", x: 0.05, y: 0.10)]
            + Label.column(x: 0.35, y: 0.10, ["Sklep Testowy", "ul. Krótka 1", "50-001 Wrocław"])
            + [Label.line("Adres doręczenia:", x: 0.05, y: 0.45)]
            + Label.column(x: 0.35, y: 0.45, ["Ewa Mazur", "os. Słoneczne 14/22", "30-002 Kraków"]),
        expected: .recipient(Address(street: "os. Słoneczne", buildingNumber: "14", apartmentNumber: "22", postalCode: "30-002", city: "Kraków"))
    )

    static let noAnchorsSingleAddress = LabelFixture(
        name: "Bez kotwic, jeden adres",
        lines: [Label.line("6200 1234 5678 9012", x: 0.1, y: 0.05)]
            + Label.column(x: 0.1, y: 0.30, ["Tomasz Lis", "Polna 2", "90-001 Łódź"]),
        expected: .recipient(Address(street: "Polna", buildingNumber: "2", postalCode: "90-001", city: "Łódź"))
    )

    /// Dwa adresy bez kotwic — kurier wybiera; większa czcionka pierwsza.
    static let noAnchorsTwoAddresses = LabelFixture(
        name: "Bez kotwic, dwa adresy do wyboru",
        lines: Label.column(x: 0.1, y: 0.05, height: 0.02, ["Sklep Mały", "ul. Krótka 1", "50-001 Wrocław"])
            + Label.column(x: 0.1, y: 0.40, height: 0.045, ["Barbara Kaczmarek", "ul. Leśna 5", "40-001 Katowice"]),
        expected: .candidates([
            Address(street: "ul. Leśna", buildingNumber: "5", postalCode: "40-001", city: "Katowice"),
            Address(street: "ul. Krótka", buildingNumber: "1", postalCode: "50-001", city: "Wrocław"),
        ])
    )

    static let uppercase = LabelFixture(
        name: "Wielkie litery",
        lines: Label.column(x: 0.05, y: 0.05, ["NADAWCA", "SKLEP TESTOWY", "UL. HANDLOWA 9", "15-001 BIAŁYSTOK"])
            + Label.column(x: 0.05, y: 0.40, ["ODBIORCA", "MARIA DĄBROWSKA", "UL. JANA PAWŁA II 12", "00-950 WARSZAWA"]),
        expected: .recipient(Address(street: "ul. Jana Pawła II", buildingNumber: "12", postalCode: "00-950", city: "Warszawa"))
    )

    static let ocrErrorsInPostalCode = LabelFixture(
        name: "Błędy OCR w kodzie pocztowym",
        lines: Label.column(x: 0.05, y: 0.05, ["Nadawca:", "ul. Fabryczna 10", "O2-OO1 Warszawa"])
            + Label.column(x: 0.05, y: 0.40, confidence: 0.7, ["Odbiorca:", "Tomasz Lewandowski", "ul. Szkolna 4", "0O-95O Warszawa"]),
        expected: .recipient(Address(street: "ul. Szkolna", buildingNumber: "4", postalCode: "00-950", city: "Warszawa"))
    )

    /// Adres wiejski: „ulica” to nazwa miejscowości.
    static let ruralWithoutStreet = LabelFixture(
        name: "Adres wiejski bez ulicy",
        lines: Label.column(x: 0.05, y: 0.40, ["Odbiorca:", "Krzysztof Zając", "Wólka Kosowska 7", "05-532 Wólka Kosowska"]),
        expected: .recipient(Address(street: "", buildingNumber: "7", postalCode: "05-532", city: "Wólka Kosowska"))
    )

    static let noisyLabel = LabelFixture(
        name: "Dużo szumu wokół adresu",
        lines: [Label.line("6200 1234 5678 9012", x: 0.1, y: 0.02, width: 0.8)]
            + Label.column(x: 0.1, y: 0.10, ["Data nadania: 2026-11-11", "Nr przesyłki: 620012345678"])
            + Label.column(x: 0.1, y: 0.30, [
                "DELIVER TO:", "Agnieszka Kamińska", "Lipowa 3a/2b", "20-001 Lublin", "tel. +48 600 100 200",
            ])
            + Label.column(x: 0.1, y: 0.70, ["Waga: 12 kg", "Pobranie: 120,00 zł", "Uwagi: zostawić u sąsiada"]),
        expected: .recipient(Address(street: "Lipowa", buildingNumber: "3A", apartmentNumber: "2B", postalCode: "20-001", city: "Lublin"))
    )

    /// Etykieta z samym nadawcą — adresu odbiorcy nie ma.
    static let senderOnly = LabelFixture(
        name: "Tylko nadawca",
        lines: Label.column(x: 0.05, y: 0.05, ["Nadawca:", "Sklep Testowy", "ul. Magazynowa 5", "02-652 Warszawa"]),
        expected: .notFound
    )

    /// Cały adres odbiorcy w jednej linii z kotwicą.
    static let addressInOneLine = LabelFixture(
        name: "Adres w jednej linii z kotwicą",
        lines: [
            Label.line("Nadawca: Sklep Testowy, ul. Magazynowa 5, 02-652 Warszawa", x: 0.05, y: 0.05, width: 0.9),
            Label.line("Odbiorca: Ewa Zielińska, ul. Lipowa 3, 20-001 Lublin", x: 0.05, y: 0.40, width: 0.9),
        ],
        expected: .recipient(Address(street: "ul. Lipowa", buildingNumber: "3", postalCode: "20-001", city: "Lublin"))
    )

    static let countryPrefixWithoutDash = LabelFixture(
        name: "Prefiks kraju i kod bez myślnika",
        lines: Label.column(x: 0.05, y: 0.30, ["Recipient:", "Jan Nowak", "ul. Morska 15/3", "PL-81225 GDYNIA"]),
        expected: .recipient(Address(street: "ul. Morska", buildingNumber: "15", apartmentNumber: "3", postalCode: "81-225", city: "Gdynia"))
    )
}
