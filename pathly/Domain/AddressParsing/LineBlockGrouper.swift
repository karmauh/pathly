import Foundation

/// Grupuje linie w bloki tekstu według położenia na zdjęciu.
///
/// Dwie linie należą do jednego bloku, gdy leżą blisko siebie w pionie i są
/// wyrównane do lewej albo jedna leży pod drugą (tekst wyśrodkowany). Dzięki temu
/// nadawca i odbiorca w dwóch kolumnach trafiają do osobnych bloków, a szeroki
/// nagłówek przewoźnika nie skleja kolumn ze sobą.
nonisolated enum LineBlockGrouper {
    /// Maksymalny odstęp w pionie, w wysokościach linii.
    static let maxLineGap = 1.2
    /// Tolerancja wyrównania do lewej (część szerokości zdjęcia).
    static let leftAlignmentTolerance = 0.06

    /// Zwraca bloki uporządkowane od góry; linie w bloku — od góry do dołu.
    static func group<Item>(_ items: [Item], box: (Item) -> TextBox) -> [[Item]] {
        // Union-find: łączymy każdą parę pasujących linii; wynik nie zależy od kolejności wejścia.
        var parent = Array(items.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }

        for i in items.indices {
            for j in items.indices where j > i && belongTogether(box(items[i]), box(items[j])) {
                parent[root(i)] = root(j)
            }
        }

        let groups = Dictionary(grouping: items.indices, by: root).values
        return groups
            .map { indices in indices.sorted { box(items[$0]).minY < box(items[$1]).minY }.map { items[$0] } }
            .sorted { box($0[0]).minY < box($1[0]).minY }
    }

    static func belongTogether(_ a: TextBox, _ b: TextBox) -> Bool {
        let lineHeight = max(a.height, b.height)
        guard a.verticalGap(to: b) <= maxLineGap * lineHeight else { return false }

        let leftAligned = abs(a.minX - b.minX) <= leftAlignmentTolerance
        let narrow = min(a.width, b.width)
        let wide = max(a.width, b.width)
        // Tekst wyśrodkowany: węższa linia prawie w całości pod szerszą, a szerokości
        // podobne — szeroki nagłówek nad dwiema kolumnami tego warunku nie spełnia.
        let stacked = narrow > 0 && narrow / wide >= 0.5 && a.horizontalOverlap(with: b) / narrow >= 0.8
        return leftAligned || stacked
    }
}
