import Foundation
import SwiftData

/// Odczyt i zapis bazy kuriera.
///
/// Protokół oddziela view model od SwiftData — w testach można podstawić
/// dowolną implementację, a view model operuje tylko na `BaseLocation`.
protocol BaseStore {
    func loadBase() throws -> BaseLocation?
    func saveBase(_ base: BaseLocation) throws
}

/// Implementacja `BaseStore` na SwiftData.
final class SwiftDataBaseStore: BaseStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadBase() throws -> BaseLocation? {
        try fetchAll().first?.location
    }

    /// Nadpisuje istniejącą bazę zamiast dodawać kolejną — w aplikacji jest
    /// tylko jedna baza. Ewentualne nadmiarowe rekordy są usuwane.
    func saveBase(_ base: BaseLocation) throws {
        let existing = try fetchAll()
        if let current = existing.first {
            current.address = base.address
            current.coordinate = base.coordinate
            current.updatedAt = .now
            existing.dropFirst().forEach(context.delete)
        } else {
            context.insert(Base(address: base.address, coordinate: base.coordinate))
        }
        try context.save()
    }

    private func fetchAll() throws -> [Base] {
        let descriptor = FetchDescriptor<Base>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try context.fetch(descriptor)
    }
}
