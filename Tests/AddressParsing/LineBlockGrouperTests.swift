import Testing
@testable import pathly

@Suite("LineBlockGrouper")
struct LineBlockGrouperTests {
    private func box(_ x: Double, _ y: Double, width: Double = 0.3, height: Double = 0.03) -> TextBox {
        TextBox(x: x, y: y, width: width, height: height)
    }

    private func group(_ boxes: [TextBox]) -> [[TextBox]] {
        LineBlockGrouper.group(boxes) { $0 }
    }

    @Test("Bliskie linie wyrównane do lewej tworzą jeden blok")
    func stackedLines() {
        let lines = [box(0.1, 0.10), box(0.1, 0.14, width: 0.2), box(0.1, 0.18)]
        #expect(group(lines) == [lines])
    }

    @Test("Duża przerwa w pionie rozdziela bloki")
    func verticalGap() {
        let top = [box(0.1, 0.10), box(0.1, 0.14)]
        let bottom = [box(0.1, 0.40), box(0.1, 0.44)]
        #expect(group(top + bottom) == [top, bottom])
    }

    @Test("Dwie kolumny w tych samych wierszach to dwa bloki")
    func twoColumns() {
        let left = [box(0.05, 0.10), box(0.05, 0.14)]
        let right = [box(0.55, 0.10), box(0.55, 0.14)]
        let blocks = group(left + right)
        #expect(blocks.count == 2)
        #expect(Set(blocks) == [left, right])
    }

    @Test("Szeroki nagłówek nie skleja dwóch kolumn")
    func wideHeader() {
        let header = box(0.05, 0.05, width: 0.9)
        let left = [box(0.05, 0.09), box(0.05, 0.13)]
        let right = [box(0.55, 0.09), box(0.55, 0.13)]
        let blocks = group([header] + left + right)
        #expect(blocks.count == 2)
        #expect(blocks.contains([header] + left))
        #expect(blocks.contains(right))
    }

    @Test("Tekst wyśrodkowany o podobnej szerokości tworzy blok")
    func centeredText() {
        let lines = [box(0.30, 0.10, width: 0.40), box(0.33, 0.14, width: 0.34)]
        #expect(group(lines) == [lines])
    }

    @Test("Wynik nie zależy od kolejności wejścia")
    func orderIndependent() {
        let lines = [box(0.1, 0.18), box(0.55, 0.10), box(0.1, 0.10), box(0.1, 0.14), box(0.55, 0.14)]
        #expect(Set(group(lines)) == Set(group(lines.reversed())))
    }
}
