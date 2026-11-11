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
    let geocodingQueue: GeocodingQueue
    /// Macierz czasów przejazdu dla algorytmu trasy (etapy 6–7).
    let travelCostProvider: any TravelCostProvider

    func makeBaseSettingsViewModel() -> BaseSettingsViewModel {
        BaseSettingsViewModel(store: baseStore, geocoder: geocoder)
    }

    func makeParcelListViewModel() -> ParcelListViewModel {
        ParcelListViewModel(store: parcelStore)
    }

    func makeAddressReviewViewModel(mode: AddressReviewViewModel.Mode) -> AddressReviewViewModel {
        AddressReviewViewModel(mode: mode, recognizer: textRecognizer, store: parcelStore, geocoding: geocodingQueue)
    }
}

extension AppDependencies {
    /// Zależności produkcyjne: dane na dysku, geokodowanie MapKit, OCR Vision,
    /// czasy przejazdu z OpenRouteService (albo przybliżenie bez klucza).
    static func live() throws -> AppDependencies {
        try make(
            container: PersistenceController.makeContainer(),
            geocoder: MapKitGeocoder(),
            textRecognizer: VisionTextRecognizer(),
            travelCostProvider: FallbackCostProvider.live(configuration: .main)
        )
    }

    private static func make(
        container: ModelContainer,
        geocoder: any Geocoder,
        textRecognizer: any TextRecognizer,
        travelCostProvider: any TravelCostProvider
    ) -> AppDependencies {
        // Jeden magazyn dla view modeli i kolejki — wspólny kontekst SwiftData.
        let parcelStore = SwiftDataParcelStore(context: container.mainContext)
        return AppDependencies(
            modelContainer: container,
            baseStore: SwiftDataBaseStore(context: container.mainContext),
            parcelStore: parcelStore,
            geocoder: geocoder,
            textRecognizer: textRecognizer,
            geocodingQueue: GeocodingQueue(geocoder: geocoder, store: parcelStore),
            travelCostProvider: travelCostProvider
        )
    }

    #if DEBUG
    /// Zależności do podglądów: dane w pamięci, bez sieci i bez OCR
    /// (czasy przejazdu z przybliżenia).
    static func preview() -> AppDependencies {
        // Kontener w pamięci nie ma powodu się nie udać — błąd tutaj to błąd programisty.
        let container = try! PersistenceController.makeContainer(inMemory: true)
        return make(
            container: container,
            geocoder: PreviewGeocoder(),
            textRecognizer: PreviewTextRecognizer(),
            travelCostProvider: HaversineCostProvider()
        )
    }
    #endif
}
