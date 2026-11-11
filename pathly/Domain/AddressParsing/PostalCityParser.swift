import Foundation

/// Linia z kodem pocztowym i miejscowością.
nonisolated struct PostalCityMatch: Hashable, Sendable {
    /// Kod w formacie `00-000`.
    var postalCode: String
    var city: String
    /// Tekst przed kodem, gdy miejscowość stoi po kodzie — np. ulica w tej samej
    /// linii: „ul. Lipowa 3, 20-001 Lublin”.
    var precedingText: String
    /// Czy kod poprawiono z błędów OCR (litery zamiast cyfr).
    var wasCorrected: Bool
}

/// Wyszukuje polski kod pocztowy (`\d{2}-\d{3}`) jako punkt zaczepienia linii
/// z miejscowością i poprawia w nim typowe błędy OCR.
nonisolated enum PostalCityParser {
    /// Litery, które OCR myli z cyframi, i ich poprawne odpowiedniki.
    static let ocrDigitFixes: [Character: Character] = [
        "O": "0", "o": "0", "I": "1", "l": "1", "|": "1", "S": "5", "B": "8",
    ]

    /// Słowa oznaczające kraj, pomijane przy odczycie miejscowości.
    static let countryWords: Set<String> = ["polska", "poland", "pl"]

    static func parse(_ line: String) -> PostalCityMatch? {
        // Każda z 5 pozycji kodu to cyfra albo litera mylona z cyfrą; myślnik bywa
        // zgubiony; opcjonalny prefiks kraju „PL-”.
        let candidate = /(?:PL\s?[-–]?\s?)?(?<first>[0-9OoIlSB|]{2})\s?[-–—]?\s?(?<second>[0-9OoIlSB|]{3})/

        for match in line.matches(of: candidate) {
            // Kod musi być osobnym „słowem” — inaczej pasowałby fragment
            // numeru telefonu czy numeru przesyłki.
            guard isBoundary(before: match.range.lowerBound, in: line),
                  isBoundary(after: match.range.upperBound, in: line)
            else { continue }

            let raw = String(match.output.first) + String(match.output.second)
            let realDigits = raw.filter(\.isNumber).count
            // Co najmniej 3 prawdziwe cyfry — chroni przed „poprawianiem” zwykłych słów.
            guard realDigits >= 3 else { continue }
            let digits = String(raw.map { ocrDigitFixes[$0] ?? $0 })
            let postalCode = "\(digits.prefix(2))-\(digits.suffix(3))"

            let before = trimmed(String(line[..<match.range.lowerBound]))
            let after = trimmed(String(line[match.range.upperBound...]))

            let city: String
            let precedingText: String
            if let afterCity = cityName(from: after) {
                // Typowy zapis: „00-950 Warszawa”.
                city = afterCity
                precedingText = before
            } else if let lastPart = before.split(separator: ",").last.map(String.init),
                      let beforeCity = cityName(from: lastPart) {
                // Zapis odwrotny: „Warszawa 00-950”.
                city = beforeCity
                precedingText = trimmed(before.split(separator: ",").dropLast().joined(separator: ","))
            } else {
                continue
            }

            return PostalCityMatch(
                postalCode: postalCode,
                city: city,
                precedingText: precedingText,
                wasCorrected: realDigits < 5
            )
        }
        return nil
    }

    /// Pierwszy człon po przecinku, bez nazwy kraju; `nil`, gdy nie ma liter.
    private static func cityName(from text: String) -> String? {
        let parts = text.split(separator: ",").map { trimmed(String($0)) }
        let city = parts.first { part in
            !countryWords.contains(LabelTextNormalizer.folded(part)) && part.contains(where: \.isLetter)
        }
        return city
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–").union(.whitespaces))
    }

    private static func isBoundary(before index: String.Index, in line: String) -> Bool {
        guard index > line.startIndex else { return true }
        let previous = line[line.index(before: index)]
        return !(previous.isLetter || previous.isNumber)
    }

    private static func isBoundary(after index: String.Index, in line: String) -> Bool {
        guard index < line.endIndex else { return true }
        let next = line[index]
        return !(next.isLetter || next.isNumber)
    }
}
