#if DEBUG
import CoreGraphics
import Foundation

/// OCR do podglądów SwiftUI — zwraca stałą, fikcyjną etykietę.
nonisolated struct PreviewTextRecognizer: TextRecognizer {
    func recognizeLines(in image: CGImage) async throws -> [RecognizedLine] {
        ["Odbiorca:", "Jan Kowalski", "ul. Długa 12/4", "31-019 Kraków"].enumerated().map { index, text in
            RecognizedLine(text: text, box: TextBox(x: 0.1, y: 0.1 + Double(index) * 0.05, width: 0.4, height: 0.03))
        }
    }
}
#endif
