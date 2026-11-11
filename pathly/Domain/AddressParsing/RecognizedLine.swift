import Foundation

/// Prostokąt na zdjęciu we współrzędnych znormalizowanych 0–1,
/// z początkiem w **lewym górnym** rogu (oś Y rośnie w dół, jak przy czytaniu).
///
/// Vision liczy oś Y od dołu — przeliczenie robi adapter OCR, nie parser.
nonisolated struct TextBox: Hashable, Sendable {
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.minX = x
        self.minY = y
        self.width = width
        self.height = height
    }

    var maxX: Double { minX + width }
    var maxY: Double { minY + height }

    /// Najmniejszy prostokąt obejmujący oba.
    func union(_ other: TextBox) -> TextBox {
        let x = min(minX, other.minX)
        let y = min(minY, other.minY)
        return TextBox(x: x, y: y, width: max(maxX, other.maxX) - x, height: max(maxY, other.maxY) - y)
    }

    /// Długość wspólnego odcinka na osi X (0, gdy się nie zachodzą).
    func horizontalOverlap(with other: TextBox) -> Double {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }

    /// Odstęp w pionie między prostokątami (0, gdy zachodzą na siebie w pionie).
    func verticalGap(to other: TextBox) -> Double {
        max(0, max(other.minY - maxY, minY - other.maxY))
    }

    /// Odstęp w poziomie między prostokątami (0, gdy zachodzą na siebie w poziomie).
    func horizontalGap(to other: TextBox) -> Double {
        max(0, max(other.minX - maxX, minX - other.maxX))
    }

    /// Najkrótsza odległość między krawędziami prostokątów.
    func distance(to other: TextBox) -> Double {
        hypot(horizontalGap(to: other), verticalGap(to: other))
    }
}

/// Jedna linia tekstu rozpoznana na etykiecie — wejście parsera.
nonisolated struct RecognizedLine: Hashable, Sendable {
    var text: String
    var box: TextBox
    /// Pewność rozpoznania zwrócona przez OCR (0–1).
    var confidence: Double

    init(text: String, box: TextBox, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}
