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
                TextField("Ulica (np. ul. Długa)", text: $viewModel.street)
                    .textContentType(.streetAddressLine1)
                    // Prefiks „ul.”, „al.” piszemy małą literą — bez automatycznej wielkiej litery.
                    .textInputAutocapitalization(.never)
                    .focused($isEditing)
                HStack {
                    TextField("Nr budynku", text: $viewModel.buildingNumber)
                        .focused($isEditing)
                    TextField("Nr lokalu", text: $viewModel.apartmentNumber)
                        .focused($isEditing)
                }
                TextField("Kod pocztowy (00-000)", text: $viewModel.postalCode)
                    .textContentType(.postalCode)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($isEditing)
                TextField("Miejscowość", text: $viewModel.city)
                    .textContentType(.addressCity)
                    .textInputAutocapitalization(.words)
                    .focused($isEditing)
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
        // Autokorekta „poprawia” nazwy własne ulic i miejscowości — wyłączamy ją.
        .autocorrectionDisabled()
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
