import Foundation

/// Listy najbliższych sąsiadów każdego punktu — ograniczają ruchy Or-opt do
/// obiecujących miejsc.
///
/// Dobra trasa prawie nigdy nie wjeżdża do przystanku z daleka, więc segment
/// warto wstawiać tylko obok punktów, z których (lub do których) jedzie się
/// najkrócej. Zamiast `n` miejsc sprawdzamy ok. `2K`: dla 150 punktów to
/// kilkukrotnie mniej pracy przy prawie tej samej jakości. Dla tras do `K`
/// przystanków listy obejmują wszystkie punkty, więc przeszukiwanie jest pełne.
nonisolated struct NeighborLists {
    static let defaultSize = 12

    /// `predecessors[v]` — punkty, z których najszybciej dojeżdża się do `v`.
    let predecessors: [[Int]]
    /// `successors[v]` — punkty, do których najszybciej dojeżdża się z `v`.
    let successors: [[Int]]

    init(table: CostTable, size: Int = defaultSize) {
        let nodes = Array(0..<table.count)
        predecessors = nodes.map { node in
            Array(nodes.filter { $0 != node }.sorted { table[$0, node] < table[$1, node] }.prefix(size))
        }
        successors = nodes.map { node in
            Array(nodes.filter { $0 != node }.sorted { table[node, $0] < table[node, $1] }.prefix(size))
        }
    }
}
