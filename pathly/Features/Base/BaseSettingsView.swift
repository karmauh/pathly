import MapKit
import SwiftUI

/// Ekran ustawień bazy: formularz adresu i podgląd zapisanego punktu na mapie.
struct BaseSettingsView: View {
    @State private var viewModel: BaseSettingsViewModel
    /// Czy któreś pole formularza ma fokus — pozwala schować klawiaturę po zapisie.
    @FocusState private var isEditing: Bool

    init(viewModel: BaseSettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                AddressFormFields(form: $viewModel.form, focus: $isEditing)
            } header: {
                Text("Adres bazy")
            } footer: {
                Text("Baza jest punktem startu i końca każdej trasy.")
            }

            Section {
                Button {
                    isEditing = false
                    Task { await viewModel.save() }
                } label: {
                    HStack {
                        Text("Zapisz bazę")
                        Spacer()
                        if viewModel.status == .saving {
                            ProgressView()
                        }
                    }
                }
                .disabled(!viewModel.canSave)

                statusMessage
            }

            if let base = viewModel.savedBase {
                Section("Zapisana baza") {
                    Text(base.address.singleLine)
                    BaseMapPreview(coordinate: base.coordinate)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Baza")
        .onAppear { viewModel.load() }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch viewModel.status {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .saved:
            Label("Baza zapisana", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .idle, .saving:
            EmptyView()
        }
    }
}

/// Mapa z pinezką bazy. `id` wymusza ponowne ustawienie kamery po zmianie bazy.
private struct BaseMapPreview: View {
    let coordinate: Coordinate

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate.clLocationCoordinate,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        ))) {
            Marker("Baza", systemImage: "house.fill", coordinate: coordinate.clLocationCoordinate)
        }
        .id(coordinate)
        .accessibilityLabel("Mapa z położeniem bazy")
    }
}

#Preview {
    NavigationStack {
        BaseSettingsView(viewModel: AppDependencies.preview().makeBaseSettingsViewModel())
    }
}
