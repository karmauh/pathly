import SwiftData
import SwiftUI

@main
struct PathlyApp: App {
    private let dependencies: AppDependencies

    init() {
        do {
            #if DEBUG
            if DemoData.isRequested {
                dependencies = try .live(inMemory: true)
                try DemoData.seed(dependencies)
                return
            }
            #endif
            dependencies = try .live()
        } catch {
            // Bez bazy danych aplikacja nie ma sensu działać dalej.
            fatalError("Nie udało się utworzyć magazynu danych: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
                // Przesyłki, których geokodowanie przerwało zamknięcie aplikacji.
                .task { dependencies.geocodingQueue.resumePending() }
        }
        .modelContainer(dependencies.modelContainer)
    }
}
