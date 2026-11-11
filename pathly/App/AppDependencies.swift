import Foundation
import SwiftData

/// Korzeń kompozycji: tworzy serwisy raz i składa z nich view modele.
///
/// Widoki dostają gotowe view modele, a zależności są wstrzykiwane przez
/// protokoły — w testach i podglądach można podmienić implementacje.
struct AppDependencies {
    let modelContainer: ModelContainer
    let baseStore: any BaseStore
    let parcelStore: any ParcelStore
    let geocoder: any Geocoder
    let textRecognizer: any TextRecognizer

    func makeBaseSettingsViewModel() -> BaseSettingsViewModel {
        BaseSettingsViewModel(store: baseStore, geocoder: geocoder)
    }

    func makeParcelListViewModel() -> ParcelListViewModel {
        ParcelListViewModel(store: parcelStore)
    }

    func makeAddressReviewViewModel(mode: AddressReviewViewModel.Mode) -> AddressReviewViewModel {
        AddressReviewViewModel(mode: mode, recognizer: textRecognizer, store: parcelStore)
    }
}

extension AppDependencies {
    /// Zależności produkcyjne: dane na dysku, geokodowanie MapKit, OCR Vision.
    static func live() throws -> AppDependencies {
        let container = try PersistenceController.makeContainer()
        return AppDependencies(
            modelContainer: container,
            baseStore: SwiftDataBaseStore(context: container.mainContext),
            parcelStore: SwiftDataParcelStore(context: container.mainContext),
            geocoder: MapKitGeocoder(),
            textRecognizer: VisionTextRecognizer()
        )
    }

    #if DEBUG
    /// Zależności do podglądów: dane w pamięci, bez sieci i bez OCR.
    static func preview() -> AppDependencies {
        // Kontener w pamięci nie ma powodu się nie udać — błąd tutaj to błąd programisty.
        let container = try! PersistenceController.makeContainer(inMemory: true)
        return AppDependencies(
            modelContainer: container,
            baseStore: SwiftDataBaseStore(context: container.mainContext),
            parcelStore: SwiftDataParcelStore(context: container.mainContext),
            geocoder: PreviewGeocoder(),
            textRecognizer: PreviewTextRecognizer()
        )
    }
    #endif
}
