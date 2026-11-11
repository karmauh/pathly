import Foundation

/// Wyodrębnia adres doręczenia (odbiorcy) z rozpoznanych linii etykiety.
///
/// Etapy:
/// 1. normalizacja tekstu i klasyfikacja linii (`LabelTextNormalizer`, `LineClassifier`);
/// 2. grupowanie linii w bloki według położenia (`LineBlockGrouper`);
/// 3. podział bloków na sekcje przy kotwicach — w ciasnym układzie jednokolumnowym
///    nadawca i odbiorca są w jednym bloku, a rozdziela je dopiero kotwica;
/// 4. budowa kandydatów: linia „kod + miejscowość” i najbliższa ulica nad nią;
/// 5. przypisanie kotwic do kandydatów i wybór odbiorcy.
///
/// Parser niczego nie zapisuje — wynik zawsze trafia na ekran podglądu do kuriera.
nonisolated struct AddressParser: Sendable {
    init() {}

    func parse(_ lines: [RecognizedLine]) -> AddressParsingResult {
        let classified = lines.compactMap(Self.classify)
        let blocks = LineBlockGrouper.group(classified) { $0.line.box }
        var candidates = blocks.flatMap(Self.sections).flatMap(Self.candidates)
        let orphanAnchors = blocks.flatMap(Self.sections).filter { section in
            section.anchor != nil && Self.candidates(in: section).isEmpty
        }
        Self.assign(orphanAnchors, to: &candidates)
        return Self.select(from: candidates)
    }
}

// MARK: - Typy pomocnicze

nonisolated private extension AddressParser {
    struct ClassifiedLine {
        var line: RecognizedLine
        var kind: LineKind
    }

    /// Fragment bloku zaczynający się od kotwicy (albo od początku bloku).
    struct Section {
        var anchor: AnchorRole?
        var anchorBox: TextBox?
        var lines: [ClassifiedLine] = []
    }

    struct Candidate {
        var address: Address
        var role: AnchorRole?
        var box: TextBox
        var lines: [RecognizedLine]
        var postalCodeCorrected: Bool

        var averageConfidence: Double {
            lines.map(\.confidence).reduce(0, +) / Double(max(lines.count, 1))
        }

        var averageLineHeight: Double {
            lines.map(\.box.height).reduce(0, +) / Double(max(lines.count, 1))
        }
    }
}

// MARK: - Etapy

nonisolated private extension AddressParser {
    static func classify(_ line: RecognizedLine) -> ClassifiedLine? {
        var line = line
        line.text = LabelTextNormalizer.normalize(line.text)
        guard !line.text.isEmpty else { return nil }
        return ClassifiedLine(line: line, kind: LineClassifier.classify(line.text))
    }

    /// Dzieli blok na sekcje przy każdej kotwicy. Tekst po kotwicy w tej samej
    /// linii staje się pierwszą linią nowej sekcji.
    static func sections(in block: [ClassifiedLine]) -> [Section] {
        var sections = [Section()]
        for item in block {
            if case .anchor(let role, let remainder) = item.kind {
                var section = Section(anchor: role, anchorBox: item.line.box)
                if !remainder.isEmpty {
                    var rest = item.line
                    rest.text = remainder
                    section.lines.append(ClassifiedLine(line: rest, kind: LineClassifier.classify(remainder)))
                }
                sections.append(section)
            } else {
                sections[sections.count - 1].lines.append(item)
            }
        }
        return sections.filter { $0.anchor != nil || !$0.lines.isEmpty }
    }

    /// Każda linia „kod + miejscowość” w sekcji daje jednego kandydata.
    static func candidates(in section: Section) -> [Candidate] {
        var result: [Candidate] = []
        var lastStreet: (parts: StreetParts, line: RecognizedLine)?

        for item in section.lines {
            switch item.kind {
            case .street(let parts):
                lastStreet = (parts, item.line)
            case .postalCity(let match):
                var usedLines = [item.line]
                var street: StreetParts?
                // Ulica w tej samej linii („ul. Lipowa 3, 20-001 Lublin”) ma pierwszeństwo.
                if let inline = match.precedingText.split(separator: ",").last,
                   let parts = StreetLineParser.parse(String(inline)) {
                    street = parts
                } else if let lastStreet {
                    street = lastStreet.parts
                    usedLines.insert(lastStreet.line, at: 0)
                }
                result.append(makeCandidate(street: street, match: match, role: section.anchor, lines: usedLines))
                // Ulica należy do jednego adresu — kolejny kod w sekcji szuka własnej.
                lastStreet = nil
            case .anchor, .noise, .other:
                continue
            }
        }
        return result
    }

    static func makeCandidate(
        street: StreetParts?,
        match: PostalCityMatch,
        role: AnchorRole?,
        lines: [RecognizedLine]
    ) -> Candidate {
        var streetName = street?.street ?? ""
        // Adres wiejski: „Wólka Kosowska 7, 05-532 Wólka Kosowska” — „ulica” to miejscowość.
        if LabelTextNormalizer.folded(streetName) == LabelTextNormalizer.folded(match.city) {
            streetName = ""
        }
        let address = Address(
            street: streetName,
            buildingNumber: street?.buildingNumber ?? "",
            apartmentNumber: street?.apartmentNumber,
            postalCode: match.postalCode,
            city: match.city
        ).normalized()

        let box = lines.dropFirst().reduce(lines[0].box) { $0.union($1.box) }
        return Candidate(
            address: address,
            role: role,
            box: box,
            lines: lines,
            postalCodeCorrected: match.wasCorrected
        )
    }

    /// Kotwica stojąca osobno (np. „Adres doręczenia:” z lewej strony formularza)
    /// wskazuje najbliższego kandydata poniżej lub obok niej.
    static func assign(_ orphans: [Section], to candidates: inout [Candidate]) {
        for orphan in orphans {
            guard let role = orphan.anchor, let anchorBox = orphan.anchorBox else { continue }
            let eligible = candidates.indices.filter { index in
                candidates[index].role == nil
                    && candidates[index].box.minY >= anchorBox.minY - anchorBox.height
            }
            if let nearest = eligible.min(by: {
                candidates[$0].box.distance(to: anchorBox) < candidates[$1].box.distance(to: anchorBox)
            }) {
                candidates[nearest].role = role
            }
        }
    }

    static func select(from candidates: [Candidate]) -> AddressParsingResult {
        let marked = candidates.filter { $0.role == .recipient }
        if !marked.isEmpty {
            let parsed = marked.map { makeParsed($0, baseConfidence: 0.95, warnings: []) }
            return .recipient(parsed.max { $0.confidence < $1.confidence }!)
        }

        // Bez kotwicy odbiorcy: odrzucamy tylko adresy oznaczone jako nadawca.
        let unmarked = candidates.filter { $0.role == nil }
        switch unmarked.count {
        case 0:
            return .notFound
        case 1:
            return .recipient(makeParsed(unmarked[0], baseConfidence: 0.7, warnings: [.recipientNotMarked]))
        default:
            // Adres odbiorcy jest zwykle drukowany większą czcionką.
            let ordered = unmarked.sorted {
                ($0.averageLineHeight, -$0.box.minY) > ($1.averageLineHeight, -$1.box.minY)
            }
            return .candidates(ordered.map { makeParsed($0, baseConfidence: 0.5, warnings: [.recipientNotMarked]) })
        }
    }

    static func makeParsed(_ candidate: Candidate, baseConfidence: Double, warnings: Set<ParsedAddress.Warning>) -> ParsedAddress {
        var warnings = warnings
        var confidence = baseConfidence
        if candidate.address.buildingNumber.isEmpty {
            warnings.insert(.missingBuildingNumber)
            confidence -= 0.3
        }
        if candidate.postalCodeCorrected {
            warnings.insert(.postalCodeCorrected)
            confidence -= 0.15
        }
        confidence *= candidate.averageConfidence
        return ParsedAddress(
            address: candidate.address,
            confidence: min(max(confidence, 0), 1),
            warnings: warnings
        )
    }
}
