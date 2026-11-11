import Testing
import UIKit
@testable import pathly

/// Test integracyjny: fikcyjna etykieta rysowana jako obraz → prawdziwe Vision → parser.
///
/// Sprawdza, czy parser radzi sobie z rzeczywistym wyjściem OCR (podział na linie,
/// współrzędne, pewność), a nie tylko z ręcznie przygotowanymi liniami.
@Suite("OCR Vision + parser (integracja)")
struct VisionOCRIntegrationTests {
    /// Rysuje linie etykiety na białym tle w proporcjach 3:4.
    static func render(_ lines: [RecognizedLine], size: CGSize = CGSize(width: 1500, height: 2000)) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for line in lines {
                let fontSize = line.box.height * size.height * 0.75
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: UIColor.black,
                ]
                let origin = CGPoint(x: line.box.minX * size.width, y: line.box.minY * size.height)
                (line.text as NSString).draw(at: origin, withAttributes: attributes)
            }
        }
        return image.cgImage!
    }

    /// Porównanie odporne na jedną znaną pomyłkę **symulatora**: „ł” czytane jako „t”.
    ///
    /// Symulator używa słabszego modelu OCR niż iPhone (Neural Engine) — na Macu
    /// te same obrazy są czytane bezbłędnie. Kod, numery, kod pocztowy i wybór
    /// bloku odbiorcy porównujemy dokładnie.
    static func matches(_ parsed: Address, _ expected: Address) -> Bool {
        func tolerant(_ text: String) -> String {
            text.replacing("ł", with: "t").replacing("Ł", with: "T")
        }
        return parsed.buildingNumber == expected.buildingNumber
            && parsed.apartmentNumber == expected.apartmentNumber
            && parsed.postalCode == expected.postalCode
            && tolerant(parsed.street) == tolerant(expected.street)
            && tolerant(parsed.city) == tolerant(expected.city)
    }

    @Test("Etykiety odczytane przez Vision dają oczekiwany adres", arguments: LabelFixture.all)
    func fixtureThroughVision(_ fixture: LabelFixture) async throws {
        let lines = try await VisionTextRecognizer().recognizeLines(in: Self.render(fixture.lines))
        let result = AddressParser().parse(lines)

        switch (fixture.expected, result) {
        case (.recipient(let expected), .recipient(let parsed)):
            #expect(Self.matches(parsed.address, expected), "\(parsed.address) ≠ \(expected). OCR: \(lines.map(\.text))")
        case (.candidates(let expected), .candidates(let parsed)):
            #expect(parsed.count == expected.count && zip(parsed, expected).allSatisfy { Self.matches($0.address, $1) },
                    "OCR: \(lines.map(\.text))")
        case (.notFound, .notFound):
            break
        default:
            Issue.record("Oczekiwano \(fixture.expected), otrzymano \(result). OCR: \(lines.map(\.text))")
        }
    }
}
