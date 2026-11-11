import Foundation
import SwiftData

/// Tworzy kontener SwiftData aplikacji. Dane są wyłącznie lokalne (bez iCloud).
enum PersistenceController {
    static let schema = Schema([Base.self, Parcel.self, Route.self])

    /// - Parameter inMemory: `true` dla testów i podglądów — nic nie trafia na dysk.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
