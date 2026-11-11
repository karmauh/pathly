import Foundation
import Observation

/// Akcje listy przesyłek. Same dane lista czyta przez `@Query`.
@Observable
final class ParcelListViewModel {
    private(set) var errorMessage: String?

    private let store: any ParcelStore

    init(store: any ParcelStore) {
        self.store = store
    }

    func delete(_ ids: Set<UUID>) {
        do {
            try store.deleteParcels(ids)
            errorMessage = nil
        } catch {
            errorMessage = "Nie udało się usunąć przesyłki."
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
