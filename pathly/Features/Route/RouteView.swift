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
    @State private var isConfirmingFinishDay = false

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
                    RouteSummary(
                        route: route,
                        progress: progress,
                        isComputing: viewModel.isComputing,
                        onRecompute: viewModel.startComputing,
                        onFinishDay: { isConfirmingFinishDay = true }
                    )
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
                if bases.isEmpty {
                    ContentUnavailableView {
                        Label("Brak bazy", systemImage: "house")
                    } description: {
                        Text("Trasa zaczyna się i kończy w bazie. Ustaw jej adres, aby wyliczyć kolejność doręczeń.")
                    } actions: {
                        NavigationLink(value: AppDestination.baseSettings) {
                            Label("Ustaw bazę", systemImage: "house")
                        }
                        .buttonStyle(.borderedProminent)
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
        }
        .toolbar {
            if route != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Przelicz trasę", systemImage: "arrow.clockwise") {
                        viewModel.startComputing()
                    }
                    .disabled(viewModel.isComputing)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Zakończ dzień", systemImage: "flag.checkered") {
                        isConfirmingFinishDay = true
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
        .confirmationDialog(
            "Zakończyć dzień?",
            isPresented: $isConfirmingFinishDay,
            titleVisibility: .visible
        ) {
            Button("Zakończ dzień", role: .destructive) { viewModel.finishDay() }
        } message: {
            Text("Doręczone przesyłki i trasa zostaną usunięte. Niedoręczone wrócą na listę jako do doręczenia, a jeszcze nieobsłużone zostaną bez zmian.")
        }
        .alert(
            "Dzień zakończony",
            isPresented: Binding(get: { viewModel.daySummaryMessage != nil }, set: { if !$0 { viewModel.dismissDaySummary() } }),
            actions: { Button("OK") {} },
            message: { Text(viewModel.daySummaryMessage ?? "") }
        )
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
    let onFinishDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Przy dużym tekście (Dynamic Type) wartości układają się jedna pod drugą.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { summaryItems; Spacer(minLength: 0); completedText }
                VStack(alignment: .leading, spacing: 4) { summaryItems; completedText }
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Czas jazdy \(RouteFormatting.duration(route.totalDuration)), dystans \(RouteFormatting.distance(route.totalDistance)), "
                    + "zrealizowano \(progress.completedCount) z \(progress.entries.count) przystanków"
            )

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
                ) {
                    Button("Zakończ dzień", action: onFinishDay)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var summaryItems: some View {
        Label(RouteFormatting.duration(route.totalDuration), systemImage: "clock")
        Label(RouteFormatting.distance(route.totalDistance), systemImage: "car")
    }

    private var completedText: some View {
        Text("\(progress.completedCount) z \(progress.entries.count)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
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
        // Tekst jest czytany razem, a przycisk zostaje osobnym, aktywnym elementem.
        .accessibilityElement(children: .contain)
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
        .accessibilityElement(children: .contain)
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
