import SwiftData
import SwiftUI

/// Ekran trasy: wyliczenie kolejności i realizacja — lista albo mapa przystanków.
struct RouteView: View {
    @State private var viewModel: RouteViewModel
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @Query(sort: \Parcel.createdAt) private var parcels: [Parcel]
    @Query private var bases: [Base]
    @AppStorage(NavigationApp.storageKey) private var navigationApp: NavigationApp = .appleMaps
    @State private var mode: DisplayMode = .list

    private let launcher = NavigationLauncher()

    init(dependencies: AppDependencies) {
        _viewModel = State(initialValue: dependencies.makeRouteViewModel())
    }

    private var route: Route? { routes.first }

    private var parcelsByID: [UUID: Parcel] {
        Dictionary(parcels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let parcelsByID = parcelsByID
        let progress = RouteProgress(
            stopOrder: route?.stopOrder ?? [],
            statuses: parcelsByID.mapValues(\.deliveryStatus)
        )
        let routeNavigation = routeNavigation(progress: progress, parcels: parcelsByID)

        Group {
            if let route, !progress.entries.isEmpty {
                VStack(spacing: 0) {
                    RouteSummary(route: route, progress: progress, isComputing: viewModel.isComputing) {
                        viewModel.startComputing()
                    }
                    Picker("Widok", selection: $mode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    switch mode {
                    case .list:
                        RouteStopList(
                            progress: progress,
                            parcels: parcelsByID,
                            onSetStatus: setStatus,
                            onNavigate: navigate,
                            routeNavigation: routeNavigation
                        )
                    case .map:
                        RouteMapView(
                            progress: progress,
                            parcels: parcelsByID,
                            base: bases.first?.coordinate,
                            onSetStatus: setStatus,
                            onNavigate: navigate,
                            routeNavigation: routeNavigation
                        )
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Brak trasy", systemImage: "map")
                } description: {
                    Text("Dodaj przesyłki, a potem wylicz najszybszą kolejność doręczeń — od bazy do bazy.")
                } actions: {
                    Button("Wylicz trasę", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        viewModel.startComputing()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isComputing)
                }
            }
        }
        .toolbar {
            if route != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Przelicz trasę", systemImage: "arrow.clockwise") {
                        viewModel.startComputing()
                    }
                    .disabled(viewModel.isComputing)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if case .computing(let phase) = viewModel.activity {
                RouteComputingBar(phase: phase, onCancel: viewModel.cancel)
            }
        }
        .animation(.default, value: viewModel.isComputing)
        .alert(
            "Nie można wyliczyć trasy",
            isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.dismissError() } }),
            actions: { Button("OK") {} },
            message: { Text(viewModel.errorMessage ?? "") }
        )
    }

    private func setStatus(_ status: DeliveryStatus, of parcelID: UUID) {
        viewModel.setStatus(status, ofParcel: parcelID)
    }

    private func navigate(to parcel: Parcel) {
        guard let coordinate = parcel.coordinate else { return }
        launcher.navigate(to: coordinate, using: navigationApp)
    }

    /// Nawigacja przez kolejne przystanki naraz — tylko w Mapach Google.
    /// W Mapach Apple karta nawiguje do jednego przystanku.
    private func routeNavigation(progress: RouteProgress, parcels: [UUID: Parcel]) -> StopNavigation? {
        guard navigationApp.supportsMultipleStops,
              let batch = NavigationBatch.next(
                  in: progress,
                  coordinates: parcels.compactMapValues(\.coordinate),
                  base: bases.first?.coordinate
              ),
              batch.stops.count > 1 || batch.returnsToBase
        else { return nil }

        return StopNavigation(
            title: batch.returnsToBase ? "Nawiguj do końca" : "Nawiguj (\(batch.stops.count))",
            hint: NavigationBatch.description(of: batch),
            action: { [launcher, navigationApp] in launcher.navigate(through: batch, using: navigationApp) }
        )
    }
}

private enum DisplayMode: String, CaseIterable, Identifiable {
    case list
    case map

    var id: Self { self }

    var title: String {
        switch self {
        case .list: "Lista"
        case .map: "Mapa"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.number"
        case .map: "map"
        }
    }
}

/// Podsumowanie trasy: czas i dystans, postęp oraz ostrzeżenia.
private struct RouteSummary: View {
    let route: Route
    let progress: RouteProgress
    let isComputing: Bool
    let onRecompute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Label(RouteFormatting.duration(route.totalDuration), systemImage: "clock")
                Label(RouteFormatting.distance(route.totalDistance), systemImage: "car")
                Spacer()
                Text("\(progress.completedCount) z \(progress.entries.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Zrealizowano \(progress.completedCount) z \(progress.entries.count) przystanków")
            }
            .font(.subheadline)

            ProgressView(value: Double(progress.completedCount), total: Double(max(progress.entries.count, 1)))
                .accessibilityHidden(true)

            if !route.isUpToDate {
                Banner(
                    text: "Przesyłki zmieniły się po wyliczeniu trasy — przelicz ją.",
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                    color: .orange
                ) {
                    Button("Przelicz", action: onRecompute)
                        .buttonStyle(.bordered)
                        .disabled(isComputing)
                }
            }
            if route.costSource == .approximate {
                Banner(
                    text: "Trasa przybliżona. "
                        + (route.approximationReason?.message ?? "Czasy przejazdu są szacowane z odległości."),
                    systemImage: "ruler",
                    color: .yellow
                )
            }
            if progress.isFinished {
                Banner(
                    text: "Wszystkie przystanki obsłużone: doręczono \(progress.deliveredCount), niedoręczono \(progress.notDeliveredCount). Wracaj do bazy.",
                    systemImage: "checkmark.seal.fill",
                    color: .green
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct Banner<Accessory: View>: View {
    let text: String
    let systemImage: String
    let color: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(10)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension Banner where Accessory == EmptyView {
    init(text: String, systemImage: String, color: Color) {
        self.init(text: text, systemImage: systemImage, color: color) { EmptyView() }
    }
}

/// Pasek postępu wyliczania trasy.
private struct RouteComputingBar: View {
    let phase: RoutePlanningPhase
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                switch phase {
                case .fetchingMatrix(let completed, let total) where total > 0:
                    Text("Pobieranie czasów przejazdu: \(completed) z \(total)")
                        .font(.subheadline)
                    ProgressView(value: Double(completed), total: Double(total))
                case .fetchingMatrix:
                    Text("Pobieranie czasów przejazdu…")
                        .font(.subheadline)
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .optimizing:
                    Text("Układanie kolejności przystanków…")
                        .font(.subheadline)
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button("Przerwij", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding()
        .background(.bar)
    }
}

/// Formatowanie wartości trasy dla kuriera.
enum RouteFormatting {
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}
