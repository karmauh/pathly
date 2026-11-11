import SwiftData
import SwiftUI

/// Ekran główny. Na razie pokazuje stan bazy; w etapie 3 zastąpi go lista przesyłek.
struct ContentView: View {
    let dependencies: AppDependencies

    @Query(sort: \Base.updatedAt, order: .reverse) private var bases: [Base]

    var body: some View {
        NavigationStack {
            Group {
                if let base = bases.first {
                    ContentUnavailableView(
                        "Baza zapisana",
                        systemImage: "house.fill",
                        description: Text(base.address.singleLine)
                    )
                } else {
                    ContentUnavailableView {
                        Label("Brak zapisanej bazy", systemImage: "house")
                    } description: {
                        Text("Zapisz adres bazy — będzie punktem startu i końca każdej trasy.")
                    } actions: {
                        NavigationLink("Ustaw bazę", value: Destination.baseSettings)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Pathly")
            .toolbar {
                NavigationLink(value: Destination.baseSettings) {
                    Label("Ustawienia bazy", systemImage: "gearshape")
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .baseSettings:
                    BaseSettingsView(viewModel: dependencies.makeBaseSettingsViewModel())
                }
            }
        }
    }

    private enum Destination: Hashable {
        case baseSettings
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    ContentView(dependencies: dependencies)
        .modelContainer(dependencies.modelContainer)
}
