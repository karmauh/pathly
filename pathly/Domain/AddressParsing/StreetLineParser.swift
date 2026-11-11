import Foundation

/// Ulica rozbita na nazwę, numer budynku i lokalu.
nonisolated struct StreetParts: Hashable, Sendable {
    var street: String
    var buildingNumber: String
    var apartmentNumber: String?
}

/// Rozbiera linię ulicy. Obsługiwane zapisy numerów:
/// `12`, `12A`, `12 A`, `12/4`, `12/4B`, `12 m. 4`, `12 lok. 4`, `nr 12`.
nonisolated enum StreetLineParser {
    /// Prefiksy jednoznacznie oznaczające linię ulicy (w zapisie po złożeniu znaków).
    static let streetPrefixes = ["ul.", "al.", "pl.", "os.", "ulica", "aleja", "plac", "osiedle", "rondo", "skwer"]

    static func hasStreetPrefix(_ line: String) -> Bool {
        let folded = LabelTextNormalizer.folded(line)
        return streetPrefixes.contains { folded.hasPrefix($0 + " ") }
    }

    static func parse(_ line: String) -> StreetParts? {
        let cleaned = LabelTextNormalizer.collapseWhitespace(line.replacing(",", with: " "))
        // name: najkrótszy tekst z co najmniej jedną literą; potem numer budynku
        // i opcjonalnie lokal — po ukośniku albo po oznaczeniu „m.”, „lok.”.
        let pattern = /^(?<name>.*?\p{L}.*?)(?:\s+nr\.?)?\s+(?<building>\d+(?:\s?[a-z])?)(?:\s*[\/\\]\s*(?<slashApartment>\d+[a-z]?)|\s+(?:lokal|lok|mieszk|m)\.?\s*(?<markedApartment>\d+[a-z]?))?$/
            .ignoresCase()

        guard let match = try? pattern.wholeMatch(in: cleaned) else { return nil }
        let apartment = match.output.slashApartment ?? match.output.markedApartment
        return StreetParts(
            street: String(match.output.name),
            buildingNumber: String(match.output.building).replacing(" ", with: "").uppercased(),
            apartmentNumber: apartment.map { String($0).uppercased() }
        )
    }
}
