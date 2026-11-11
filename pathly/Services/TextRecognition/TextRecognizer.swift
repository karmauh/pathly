import CoreGraphics
import Foundation

/// Rozpoznawanie tekstu na zdjęciu etykiety. Implementacja produkcyjna: `VisionTextRecognizer`.
///
/// Protokół zwraca linie w formacie parsera (`RecognizedLine`), więc parser
/// i view model nie wiedzą nic o Vision.
protocol TextRecognizer: Sendable {
    func recognizeLines(in image: CGImage) async throws -> [RecognizedLine]
}

/// Przeliczenia współrzędnych Vision na współrzędne parsera.
nonisolated enum VisionGeometry {
    /// Vision opisuje linię czterema narożnikami we współrzędnych 0–1
    /// z początkiem w **lewym dolnym** rogu. Parser oczekuje prostokąta
    /// z początkiem w **lewym górnym** rogu — odwracamy oś Y.
    static func textBox(corners: [(x: Double, y: Double)]) -> TextBox {
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return TextBox(x: minX, y: 1 - maxY, width: maxX - minX, height: maxY - minY)
    }
}
