import CoreGraphics
import Foundation
import Vision

/// OCR etykiet przez `RecognizeTextRequest` (Vision).
nonisolated struct VisionTextRecognizer: TextRecognizer {
    /// Polski dla adresów, angielski dla kotwic typu „Ship to”.
    static let languages = [Locale.Language(identifier: "pl-PL"), Locale.Language(identifier: "en-US")]

    /// `@concurrent` — rozpoznawanie zawsze poza głównym wątkiem. Przy włączonym
    /// „Approachable Concurrency” zwykła funkcja `nonisolated async` działałaby
    /// na aktorze wywołującego, czyli tu na `MainActor`.
    @concurrent
    func recognizeLines(in image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = Self.languages
        // Korekta językowa pomaga przy nazwach ulic; kody pocztowe i tak
        // naprawia parser.
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: image, orientation: .up)
        return observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                .map { (x: Double($0.x), y: Double($0.y)) }
            return RecognizedLine(
                text: best.string,
                box: VisionGeometry.textBox(corners: corners),
                confidence: Double(best.confidence)
            )
        }
    }
}
