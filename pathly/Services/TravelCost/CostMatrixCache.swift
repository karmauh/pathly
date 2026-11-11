import Foundation

/// Pamięć podręczna macierzy z sieci dróg, zapisywana w katalogu Caches.
///
/// Ponowne wyliczenie trasy dla tych samych punktów nie zużywa limitu zapytań,
/// także po ponownym uruchomieniu aplikacji. Kluczem jest lista współrzędnych
/// w danej kolejności (macierz odnosi się do indeksów), zaokrąglonych do
/// 5 miejsc po przecinku (~1 m). Trzymamy kilka ostatnio używanych macierzy.
///
/// Przybliżeń nie zapisujemy — po powrocie sieci chcemy pobrać prawdziwe dane.
/// Błędy zapisu są pomijane: pamięć podręczna to tylko optymalizacja.
actor CostMatrixCache {
    /// Domyślny katalog w Caches aplikacji (system może go wyczyścić).
    static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "TravelCost", directoryHint: .isDirectory)
    }

    private let fileURL: URL
    private let capacity: Int
    /// Od ostatnio używanej; `nil`, dopóki nie wczytano pliku.
    private var entries: [Entry]?

    init(directory: URL = CostMatrixCache.defaultDirectory, capacity: Int = 5) {
        self.fileURL = directory.appending(path: "cost-matrices.json")
        self.capacity = capacity
    }

    func matrix(for points: [Coordinate]) -> CostMatrix? {
        let key = Self.key(for: points)
        var entries = loadedEntries()
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        save(entries)
        return entry.matrix
    }

    func store(_ matrix: CostMatrix, for points: [Coordinate]) {
        guard matrix.source == .roadNetwork, matrix.count == points.count else { return }
        let key = Self.key(for: points)
        var entries = loadedEntries().filter { $0.key != key }
        entries.insert(Entry(key: key, matrix: matrix), at: 0)
        save(Array(entries.prefix(capacity)))
    }

    /// Współrzędne zaokrąglone do ~1 m, w kolejności punktów.
    static func key(for points: [Coordinate]) -> [Int64] {
        points.flatMap { [Int64(($0.latitude * 1e5).rounded()), Int64(($0.longitude * 1e5).rounded())] }
    }

    // MARK: Plik

    private func loadedEntries() -> [Entry] {
        if let entries { return entries }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        entries = loaded
        return loaded
    }

    private func save(_ newEntries: [Entry]) {
        entries = newEntries
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(newEntries).write(to: fileURL, options: .atomic)
        } catch {
            // Bez zapisu na dysku macierz zostaje w pamięci do końca sesji.
        }
    }

    nonisolated struct Entry: Codable, Sendable {
        let key: [Int64]
        let matrix: CostMatrix
    }
}
