import Foundation

/// Porządkuje tekst linii z OCR, zanim trafi do klasyfikacji.
///
/// Celowo **nie** poprawia tu błędów OCR typu `O`→`0` — to robi wyłącznie
/// `PostalCityParser` w miejscu kodu pocztowego, aby nie psuć nazw ulic.
nonisolated enum LabelTextNormalizer {
    static let polish = Locale(identifier: "pl_PL")

    /// Prefiksy ulic zapisywane małą literą.
    static let streetPrefixes: Set<String> = ["ul.", "al.", "pl.", "os."]

    /// Liczby rzymskie występujące w nazwach ulic („Jana Pawła II”) — bez zmiany wielkości liter.
    static let romanNumerals: Set<String> = [
        "II", "III", "IV", "VI", "VII", "VIII", "IX", "XI", "XII", "XIII", "XIV", "XV", "XX",
    ]

    static func normalize(_ text: String) -> String {
        fixCase(spaceAfterStreetPrefix(collapseWhitespace(text)))
    }

    /// Przycina i scala wielokrotne białe znaki w jedną spację.
    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// „ul.Długa” → „ul. Długa” (OCR często gubi spację po kropce).
    static func spaceAfterStreetPrefix(_ text: String) -> String {
        text.replacing(/^(ul|al|pl|os)\.(?=\p{L})/.ignoresCase()) { match in
            "\(match.output.1). "
        }
    }

    /// Wyrazy pisane w całości wielkimi literami zamienia na zapis tytułowy
    /// („WARSZAWA” → „Warszawa”), prefiksy ulic na małe litery („UL.” → „ul.”).
    /// Wyrazy z cyframi i liczby rzymskie zostają bez zmian.
    static func fixCase(_ text: String) -> String {
        text.split(separator: " ").map { word in
            let word = String(word)
            let letters = word.filter(\.isLetter)
            guard letters.count >= 2,
                  letters.allSatisfy(\.isUppercase),
                  !word.contains(where: \.isNumber),
                  !romanNumerals.contains(word)
            else { return word }

            let lowercased = word.lowercased(with: polish)
            if streetPrefixes.contains(lowercased) { return lowercased }
            return word.capitalized(with: polish)
        }
        .joined(separator: " ")
    }

    /// Tekst do porównań: małe litery, bez znaków diakrytycznych.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: polish)
    }
}
