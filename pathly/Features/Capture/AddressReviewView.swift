import MapKit
import SwiftUI

/// Ekran podglądu adresu: zdjęcie etykiety (tylko w pamięci) i formularz do
/// poprawienia. Kurier zatwierdza albo odrzuca — parser niczego nie zapisuje sam.
struct AddressReviewView: View {
    @State private var viewModel: AddressReviewViewModel
    @State private var isPhotoEnlarged = false
    @FocusState private var isEditing: Bool
    @Environment(\.dismiss) private var dismiss

    /// Zdjęcie etykiety; `nil` przy ręcznym dodawaniu i edycji.
    private let photo: UIImage?
    /// Wywoływane po zakończeniu. `next == true` — kurier chce od razu kolejną paczkę.
    private let onFinish: (_ next: Bool) -> Void

    init(viewModel: AddressReviewViewModel, photo: UIImage? = nil, onFinish: @escaping (_ next: Bool) -> Void = { _ in }) {
        _viewModel = State(initialValue: viewModel)
        self.photo = photo
        self.onFinish = onFinish
    }

    var body: some View {
        Form {
            if let photo {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { isPhotoEnlarged = true }
                        .accessibilityLabel("Zdjęcie etykiety")
                        .accessibilityHint("Dotknij, aby powiększyć")
                }
            }

            switch viewModel.phase {
            case .recognizing:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Odczytuję adres z etykiety…")
                    }
                }
            case .choosingCandidate:
                candidatesSection
            case .reviewing:
                reviewSections
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Odrzuć", role: .cancel) { finish(next: false) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Zatwierdź") { approve(next: false) }
                    .disabled(!viewModel.canApprove)
            }
        }
        .onAppear { viewModel.load() }
        .task {
            if viewModel.mode == .photo, let photo, let image = LabelImage.prepareForRecognition(photo) {
                await viewModel.recognize(image)
            }
        }
        .fullScreenCover(isPresented: $isPhotoEnlarged) {
            if let photo {
                EnlargedPhotoView(photo: photo)
            }
        }
    }

    private var candidatesSection: some View {
        Section {
            ForEach(viewModel.candidates, id: \.self) { candidate in
                Button {
                    viewModel.choose(candidate)
                } label: {
                    Text(candidate.address.singleLine)
                        .foregroundStyle(.primary)
                }
            }
            Button("Wpiszę adres ręcznie") { viewModel.enterManually() }
        } header: {
            Text("Wybierz adres odbiorcy")
        } footer: {
            Text("Na etykiecie nie oznaczono odbiorcy, a znaleziono kilka adresów.")
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        if let notice = viewModel.notice ?? viewModel.geocodingProblem {
            Section {
                Label(notice, systemImage: "exclamationmark.bubble")
                    .foregroundStyle(.orange)
            }
        }

        if viewModel.canChooseLocation {
            locationCandidatesSection
        }

        Section {
            AddressFormFields(form: $viewModel.form, highlighted: viewModel.fieldsToCheck, focus: $isEditing)
        } header: {
            Text("Adres doręczenia")
        } footer: {
            if !viewModel.parserFlaggedFields.isEmpty {
                Text("Wyróżnione pola zostały poprawione lub uzupełnione automatycznie — sprawdź je.")
            }
        }

        if let error = viewModel.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }

        if viewModel.mode == .photo {
            Section {
                Button {
                    approve(next: true)
                } label: {
                    Label("Zatwierdź i następna", systemImage: "camera")
                }
                .disabled(!viewModel.canApprove)
            }
        }
    }

    /// Wybór miejsca, gdy adres pasuje do kilku odległych punktów.
    private var locationCandidatesSection: some View {
        let numbered = Array(viewModel.locationCandidates.enumerated())
        return Section {
            Map(initialPosition: .automatic) {
                ForEach(numbered, id: \.offset) { index, candidate in
                    Marker("\(index + 1)", coordinate: candidate.coordinate.clLocationCoordinate)
                }
            }
            .frame(height: 200)
            .listRowInsets(EdgeInsets())
            .accessibilityHidden(true)

            ForEach(numbered, id: \.offset) { index, candidate in
                Button {
                    if viewModel.chooseLocation(candidate) { finish(next: false) }
                } label: {
                    Label {
                        Text(candidate.label)
                            .foregroundStyle(.primary)
                    } icon: {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.red, in: .circle)
                    }
                }
                .accessibilityLabel("Miejsce \(index + 1): \(candidate.label)")
            }
        } header: {
            Text("Wybierz właściwe miejsce")
        } footer: {
            Text("Do adresu pasuje kilka miejsc. Wybierz właściwe albo popraw adres poniżej.")
        }
    }

    private func approve(next: Bool) {
        isEditing = false
        if viewModel.approve() {
            finish(next: next)
        }
    }

    private func finish(next: Bool) {
        onFinish(next)
        dismiss()
    }
}

/// Powiększone zdjęcie etykiety z możliwością przybliżania.
private struct EnlargedPhotoView: View {
    let photo: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom)
                .gesture(MagnifyGesture().onChanged { zoom = max(1, $0.magnification) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .toolbar {
                    Button("Zamknij") { dismiss() }
                }
        }
    }
}

#Preview("Ręcznie") {
    NavigationStack {
        AddressReviewView(viewModel: AppDependencies.preview().makeAddressReviewViewModel(mode: .manual))
    }
}
