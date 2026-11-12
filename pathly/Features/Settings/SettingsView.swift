import SwiftData
import SwiftUI

/// Ustawienia: baza kuriera i aplikacja do nawigacji.
struct SettingsView: View {
    @Query private var bases: [Base]
    @AppStorage(NavigationApp.storageKey) private var navigationApp: NavigationApp = .appleMaps

    var body: some View {
        Form {
            Section {
                NavigationLink(value: AppDestination.baseSettings) {
                    LabeledContent {
                        Text(bases.first?.address.singleLine ?? "Nie ustawiono")
                            .foregroundStyle(bases.isEmpty ? .orange : .secondary)
                            .lineLimit(2)
                    } label: {
                        Label("Baza", systemImage: "house")
                    }
                }
            } footer: {
                Text("Trasa zaczyna się i kończy w bazie.")
            }

            Section {
                Picker("Nawiguj w", selection: $navigationApp) {
                    ForEach(NavigationApp.allCases) { app in
                        Text(app.title).tag(app)
                    }
                }
            } header: {
                Text("Nawigacja")
            } footer: {
                Text("Mapy Google prowadzą przez kilka kolejnych przystanków naraz (do 9), a na końcu trasy z powrotem do bazy. Mapy Apple nie przyjmują wielu przystanków w linku — prowadzą do jednego. Bez zainstalowanych Map Google trasa otworzy się w przeglądarce.")
            }
        }
        .navigationTitle("Ustawienia")
    }
}
