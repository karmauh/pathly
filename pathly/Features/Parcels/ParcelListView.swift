import PhotosUI
import SwiftData
import SwiftUI

/// Ekran główny: lista przesyłek bieżącej trasy i dodawanie nowych.
///
/// Przepływ dodawania ze zdjęcia: aparat → podgląd adresu → zatwierdzenie
/// (opcjonalnie „Zatwierdź i następna” — aparat otwiera się ponownie).
struct ParcelListView: View {
    let dependencies: AppDependencies

    @State private var viewModel: ParcelListViewModel
    @Query(sort: \Parcel.createdAt) private var parcels: [Parcel]
    @Query private var bases: [Base]

    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var photoSelection: PhotosPickerItem?
    /// Zdjęcie z aparatu czeka, aż zamknie się ekran aparatu — dopiero wtedy
    /// można pokazać kolejny arkusz.
    @State private var capturedPhoto: UIImage?
    @State private var review: ReviewRequest?
    /// Źródło, z którego otworzyć kolejne zdjęcie po „Zatwierdź i następna”.
    @State private var nextSource: CaptureSource?

    private var geocoding: GeocodingQueue { dependencies.geocodingQueue }

    /// Przesyłki, których położenia nie udało się ustalić — blokują wyliczenie trasy.
    private var parcelsNeedingAttention: [Parcel] {
        parcels.filter { $0.geocodingStatus.needsAttention && !geocoding.isScheduled($0.id) }
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: dependencies.makeParcelListViewModel())
    }

    var body: some View {
        List {
            if bases.isEmpty {
                Section {
                    NavigationLink(value: AppDestination.baseSettings) {
                        Label("Ustaw bazę — bez niej nie wyliczysz trasy", systemImage: "house")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !parcelsNeedingAttention.isEmpty {
                attentionSection
            }

            if parcels.isEmpty {
                ContentUnavailableView {
                    Label("Brak przesyłek", systemImage: "shippingbox")
                } description: {
                    Text("Zrób zdjęcie listu przewozowego albo wpisz adres ręcznie.")
                } actions: {
                    addMenu
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                }
                .listRowBackground(Color.clear)
            } else {
                Section("Przesyłki (\(parcels.count))") {
                    ForEach(parcels) { parcel in
                        Button {
                            review = ReviewRequest(mode: .edit(parcel.id))
                        } label: {
                            ParcelRow(parcel: parcel, isScheduled: geocoding.isScheduled(parcel.id))
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        viewModel.delete(Set(offsets.map { parcels[$0].id }))
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        .safeAreaInset(edge: .bottom) {
            if geocoding.isRunning {
                GeocodingProgressBar(queue: geocoding)
            }
        }
        .animation(.default, value: geocoding.isRunning)
        .alert(
            "Błąd",
            isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.dismissError() } }),
            actions: { Button("OK") {} },
            message: { Text(viewModel.errorMessage ?? "") }
        )
        .fullScreenCover(isPresented: $isCameraPresented, onDismiss: showCapturedPhoto) {
            CameraPicker(
                onCapture: { image in
                    capturedPhoto = image
                    isCameraPresented = false
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) {
            Task { await showSelectedPhoto() }
        }
        .sheet(item: $review, onDismiss: openNextSource) { request in
            NavigationStack {
                AddressReviewView(
                    viewModel: dependencies.makeAddressReviewViewModel(mode: request.mode),
                    photo: request.photo
                ) { next in
                    nextSource = next ? request.source : nil
                }
            }
            // Przypadkowe przesunięcie arkusza nie może zgubić odczytanego adresu.
            .interactiveDismissDisabled()
        }
    }

    private var attentionSection: some View {
        let count = parcelsNeedingAttention.count
        let hasTechnicalFailures = parcelsNeedingAttention.contains { $0.geocodingStatus == .failed }
        return Section {
            Label(
                count == 1 ? "1 przesyłka wymaga poprawy" : "Przesyłki wymagające poprawy: \(count)",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            if hasTechnicalFailures {
                Button("Ponów ustalanie położenia", systemImage: "arrow.clockwise") {
                    geocoding.retryFailed()
                }
            }
        } footer: {
            Text("Dotknij przesyłkę, aby poprawić adres. Bez położenia wszystkich przesyłek nie wyliczysz trasy.")
        }
    }

    private var addMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button("Zrób zdjęcie etykiety", systemImage: "camera") { isCameraPresented = true }
            }
            Button("Wybierz zdjęcie z galerii", systemImage: "photo") { isPhotoPickerPresented = true }
            Button("Wpisz adres ręcznie", systemImage: "keyboard") { review = ReviewRequest(mode: .manual) }
        } label: {
            Label("Dodaj przesyłkę", systemImage: "plus")
        }
    }

    private func showCapturedPhoto() {
        guard let photo = capturedPhoto else { return }
        capturedPhoto = nil
        review = ReviewRequest(mode: .photo, photo: photo, source: .camera)
    }

    private func showSelectedPhoto() async {
        guard let item = photoSelection else { return }
        photoSelection = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let photo = UIImage(data: data) else {
            viewModel.reportPhotoLoadFailure()
            return
        }
        review = ReviewRequest(mode: .photo, photo: photo, source: .library)
    }

    private func openNextSource() {
        switch nextSource {
        case .camera: isCameraPresented = true
        case .library: isPhotoPickerPresented = true
        case nil: break
        }
        nextSource = nil
    }
}

private enum CaptureSource {
    case camera
    case library
}

/// Żądanie otwarcia ekranu podglądu. Zdjęcie żyje tylko tak długo jak ten arkusz.
private struct ReviewRequest: Identifiable {
    let id = UUID()
    let mode: AddressReviewViewModel.Mode
    var photo: UIImage?
    var source: CaptureSource?
}

/// Pasek postępu geokodowania nad dolną krawędzią listy.
private struct GeocodingProgressBar: View {
    let queue: GeocodingQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ustalanie położenia: \(min(queue.completed + 1, queue.total)) z \(queue.total)")
                .font(.subheadline)
            ProgressView(value: Double(queue.completed), total: Double(max(queue.total, 1)))
            if queue.isWaitingForRateLimit {
                Text("Przekroczono limit zapytań — czekam i spróbuję ponownie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

/// Wiersz listy: adres i stan geokodowania.
private struct ParcelRow: View {
    let parcel: Parcel
    /// Przesyłka czeka w kolejce geokodowania (także przy ponowieniu po błędzie).
    let isScheduled: Bool

    private var status: GeocodingStatus {
        isScheduled ? .pending : parcel.geocodingStatus
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(parcel.address.streetLine)
                Text("\(parcel.address.postalCode) \(parcel.address.city)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            statusIcon
        }
        .accessibilityElement(children: .combine)
    }

    private var problem: String? {
        switch status {
        case .notFound: "Nie znaleziono adresu — popraw go"
        case .ambiguous: "Kilka pasujących miejsc — wybierz właściwe"
        case .failed: "Błąd połączenia — ponów lub popraw adres"
        case .pending, .succeeded: nil
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Czeka na ustalenie położenia")
        case .succeeded:
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Położenie ustalone")
        case .notFound, .ambiguous, .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Adres wymaga poprawy")
        }
    }
}
