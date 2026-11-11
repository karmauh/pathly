import SwiftData
import SwiftUI

/// Cele nawigacji aplikacji.
enum AppDestination: Hashable {
    case baseSettings
}

/// Korzeń interfejsu: stos nawigacji z listą przesyłek jako ekranem głównym.
struct ContentView: View {
    let dependencies: AppDependencies

    var body: some View {
        NavigationStack {
            ParcelListView(dependencies: dependencies)
                .navigationTitle("Przesyłki")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: AppDestination.baseSettings) {
                            Label("Ustawienia bazy", systemImage: "gearshape")
                        }
                    }
                }
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .baseSettings:
                        BaseSettingsView(viewModel: dependencies.makeBaseSettingsViewModel())
                    }
                }
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    ContentView(dependencies: dependencies)
        .modelContainer(dependencies.modelContainer)
}
