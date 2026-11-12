import SwiftData
import SwiftUI

/// Cele nawigacji aplikacji.
enum AppDestination: Hashable {
    case baseSettings
}

/// Korzeń interfejsu: karty Przesyłki, Trasa i Ustawienia, każda z własnym stosem nawigacji.
struct ContentView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            Tab("Przesyłki", systemImage: "shippingbox") {
                stack {
                    ParcelListView(dependencies: dependencies)
                        .navigationTitle("Przesyłki")
                }
            }
            Tab("Trasa", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                stack {
                    RouteView(dependencies: dependencies)
                        .navigationTitle("Trasa")
                }
            }
            Tab("Ustawienia", systemImage: "gearshape") {
                stack {
                    SettingsView()
                }
            }
        }
    }

    private func stack(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            content()
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
