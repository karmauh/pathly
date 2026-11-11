import Foundation
import SwiftData

/// Korzeń kompozycji: tworzy serwisy raz i składa z nich view modele.
///
/// Widoki dostają gotowe view modele, a zależności są wstrzykiwane przez
/// protokoły — w testach i podglądach można podmienić implementacje.
struct AppDependencies {
    let modelContainer: ModelContainer
    let baseStore: any BaseStore
    let geocoder: any Geocoder

    func makeBaseSettingsViewModel() -> BaseSettingsViewModel {
        BaseSettingsViewModel(store: baseStore, geocoder: geocoder)
    }
}

extension AppDependencies {
    /// Zależności produkcyjne: dane na dysku, geokodowanie przez MapKit.
    static func live() throws -> AppDependencies {
        let container = try PersistenceController.makeContainer()
        return AppDependencies(
            modelContainer: container,
            baseStore: SwiftDataBaseStore(context: container.mainContext),
            geocoder: MapKitGeocoder()
        )
    }

    #if DEBUG
    /// Zależności do podglądów: dane w pamięci, geokoder bez sieci.
    static func preview() -> AppDependencies {
        // Kontener w pamięci nie ma powodu się nie udać — błąd tutaj to błąd programisty.
        let container = try! PersistenceController.makeContainer(inMemory: true)
        return AppDependencies(
            modelContainer: container,
            baseStore: SwiftDataBaseStore(context: container.mainContext),
            geocoder: PreviewGeocoder()
        )
    }
    #endif
}
