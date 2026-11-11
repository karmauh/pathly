import Testing
@testable import pathly

@Suite("LabelTextNormalizer")
struct LabelTextNormalizerTests {
    @Test("Normalizacja linii", arguments: [
        ("  ul.   Długa  12 ", "ul. Długa 12"),
        ("UL. JANA PAWŁA II 12", "ul. Jana Pawła II 12"),
        ("00-950 WARSZAWA", "00-950 Warszawa"),
        ("BIELSKO-BIAŁA", "Bielsko-Biała"),
        ("ul.Długa 5", "ul. Długa 5"),
        ("AL.Niepodległości 12A", "al. Niepodległości 12A"),
        ("Mieszana Wielkość Liter", "Mieszana Wielkość Liter"),
        ("12A/4B", "12A/4B"),
        ("al. Jana Pawła Il 45", "al. Jana Pawła II 45"),
        ("UL. JANA PAWŁA || 12", "ul. Jana Pawła II 12"),
        ("ul. Bolesława lII 3", "ul. Bolesława III 3"),
        ("Il piętro", "Il piętro"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(LabelTextNormalizer.normalize(input) == expected)
    }

    @Test("Wielka pierwsza litera miejscowości")
    func capitalizesFirstLetter() {
        #expect(LabelTextNormalizer.capitalizingFirstLetter("łódź") == "Łódź")
        #expect(LabelTextNormalizer.capitalizingFirstLetter("Kraków") == "Kraków")
        #expect(LabelTextNormalizer.capitalizingFirstLetter("") == "")
    }

    @Test("Złożenie znaków do porównań")
    func folding() {
        #expect(LabelTextNormalizer.folded("Doręczyć DO") == "doreczyc do")
    }
}
