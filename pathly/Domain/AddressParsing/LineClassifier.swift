import Foundation

/// Rola kotwicy — etykiety pola na liście przewozowym.
nonisolated enum AnchorRole: Hashable, Sendable {
    case recipient
    case sender
}

/// Znaczenie pojedynczej linii etykiety.
nonisolated enum LineKind: Hashable, Sendable {
    /// Kotwica („Odbiorca:”, „Nadawca”). `remainder` to tekst po kotwicy
    /// w tej samej linii, np. nazwisko w „Odbiorca: Jan Kowalski”.
    case anchor(AnchorRole, remainder: String)
    case postalCity(PostalCityMatch)
    case street(StreetParts)
    /// Numery przesyłek, kody kreskowe, wagi, telefony, uwagi — ignorowane.
    case noise
    /// Pozostałe: imiona, nazwy firm, nagłówki przewoźnika.
    case other
}

/// Przypisuje linii jej znaczenie na podstawie samego tekstu.
nonisolated enum LineClassifier {
    struct Anchor: Sendable {
        /// Fraza po złożeniu znaków (małe litery, bez diakrytyków).
        let phrase: String
        let role: AnchorRole
        /// Krótkie, wieloznaczne frazy („do”, „od”) uznajemy za kotwicę
        /// tylko z dwukropkiem albo jako całą linię.
        let isShort: Bool
    }

    /// Kotwice od najdłuższej — „odbiorca” musi wygrać z „od:”.
    static let anchors: [Anchor] = [
        Anchor(phrase: "adres doreczenia", role: .recipient, isShort: false),
        Anchor(phrase: "adres dostawy", role: .recipient, isShort: false),
        Anchor(phrase: "doreczyc do", role: .recipient, isShort: false),
        Anchor(phrase: "dostarczyc do", role: .recipient, isShort: false),
        Anchor(phrase: "odbiorca", role: .recipient, isShort: false),
        Anchor(phrase: "recipient", role: .recipient, isShort: false),
        Anchor(phrase: "consignee", role: .recipient, isShort: false),
        Anchor(phrase: "deliver to", role: .recipient, isShort: false),
        Anchor(phrase: "receiver", role: .recipient, isShort: false),
        Anchor(phrase: "ship to", role: .recipient, isShort: false),
        Anchor(phrase: "do", role: .recipient, isShort: true),
        Anchor(phrase: "return address", role: .sender, isShort: false),
        Anchor(phrase: "adres zwrotny", role: .sender, isShort: false),
        Anchor(phrase: "return to", role: .sender, isShort: false),
        Anchor(phrase: "zwrot do", role: .sender, isShort: false),
        Anchor(phrase: "nadawca", role: .sender, isShort: false),
        Anchor(phrase: "shipper", role: .sender, isShort: false),
        Anchor(phrase: "sender", role: .sender, isShort: false),
        Anchor(phrase: "from", role: .sender, isShort: true),
        Anchor(phrase: "od", role: .sender, isShort: true),
    ].sorted { $0.phrase.count > $1.phrase.count }

    /// Etykiety pól, które nie są adresem (po złożeniu znaków).
    static let noiseLabels = [
        "nr przesylki", "numer przesylki", "nr paczki", "tracking", "waga", "weight",
        "uwagi", "data", "date", "pobranie", "cod", "ref", "zawartosc", "tel", "telefon",
        "phone", "e-mail", "email",
    ]

    static func classify(_ text: String) -> LineKind {
        if let (role, remainder) = matchAnchor(text) {
            return .anchor(role, remainder: remainder)
        }
        if isNoise(text) { return .noise }
        if let match = PostalCityParser.parse(text) { return .postalCity(match) }
        if let street = StreetLineParser.parse(text) { return .street(street) }
        if StreetLineParser.hasStreetPrefix(text) {
            // Ulica bez numeru — kurier uzupełni go na ekranie podglądu.
            return .street(StreetParts(street: text, buildingNumber: "", apartmentNumber: nil))
        }
        return .other
    }

    static func matchAnchor(_ text: String) -> (AnchorRole, String)? {
        let folded = LabelTextNormalizer.folded(text)
        for anchor in anchors where folded.hasPrefix(anchor.phrase) {
            let rest = folded.dropFirst(anchor.phrase.count)
            let isWholeWord = rest.isEmpty || rest.first == ":" || (!anchor.isShort && rest.first == " ")
            guard isWholeWord else { continue }
            // Złożenie znaków nie zmienia liczby znaków dla polskich liter,
            // więc resztę możemy wyciąć z oryginalnego tekstu.
            let remainder = text.dropFirst(anchor.phrase.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespaces))
            return (anchor.role, remainder)
        }
        return nil
    }

    static func isNoise(_ text: String) -> Bool {
        let folded = LabelTextNormalizer.folded(text)
        let startsWithLabel = noiseLabels.contains { label in
            guard folded.hasPrefix(label) else { return false }
            // Etykieta to całe słowo: „tel.” tak, „Telimena” nie.
            return folded.dropFirst(label.count).first.map { !$0.isLetter } ?? true
        }
        if startsWithLabel || folded.contains("+48") { return true }
        if text.contains(/\d+(?:[.,]\d+)?\s?kg(?!\p{L})/.ignoresCase()) { return true }

        // Długie ciągi cyfr bez słów: numery przesyłek, kody kreskowe, telefony.
        let digits = text.filter(\.isNumber).count
        let letters = text.filter(\.isLetter).count
        return digits >= 8 && letters < digits
    }
}
