import SwiftUI

/// Lista przystanków w kolejności trasy z wyróżnionym następnym przystankiem.
struct RouteStopList: View {
    let progress: RouteProgress
    let parcels: [UUID: Parcel]
    let onSetStatus: (DeliveryStatus, UUID) -> Void
    let onNavigate: (Parcel) -> Void
    /// Nawigacja z bieżącego przystanku przez kolejne — gdy aplikacja ją obsługuje.
    let routeNavigation: StopNavigation?

    var body: some View {
        List {
            if let current = progress.current, let parcel = parcels[current.parcelID] {
                Section {
                    StopActionCard(
                        entry: current,
                        parcel: parcel,
                        isCurrent: true,
                        navigation: routeNavigation ?? .single { onNavigate(parcel) },
                        onSetStatus: onSetStatus
                    )
                } header: {
                    Text("Następny przystanek")
                } footer: {
                    if let hint = routeNavigation?.hint {
                        Text(hint)
                    }
                }
            }

            Section {
                ForEach(progress.entries) { entry in
                    if let parcel = parcels[entry.parcelID] {
                        RouteStopRow(entry: entry, parcel: parcel, isCurrent: entry.id == progress.current?.id, onNavigate: onNavigate)
                            .swipeActions(edge: .leading) {
                                if entry.status != .delivered {
                                    Button("Doręczona", systemImage: "checkmark") { onSetStatus(.delivered, entry.parcelID) }
                                        .tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if entry.status != .notDelivered {
                                    Button("Niedoręczona", systemImage: "xmark") { onSetStatus(.notDelivered, entry.parcelID) }
                                        .tint(.orange)
                                }
                                if entry.status != .pending {
                                    Button("Cofnij", systemImage: "arrow.uturn.backward") { onSetStatus(.pending, entry.parcelID) }
                                }
                            }
                            .contextMenu {
                                StatusMenuItems(entry: entry, onSetStatus: onSetStatus)
                            }
                    }
                }
            } header: {
                Text("Przystanki (\(progress.entries.count))")
            } footer: {
                Text("Przesuń przystanek w prawo, aby oznaczyć doręczenie, w lewo — brak doręczenia.")
            }
        }
    }
}

/// Wiersz przystanku: numer, adres, status i nawigacja.
private struct RouteStopRow: View {
    let entry: RouteProgress.Entry
    let parcel: Parcel
    let isCurrent: Bool
    let onNavigate: (Parcel) -> Void

    var body: some View {
        HStack(spacing: 12) {
            StopNumberBadge(entry: entry, isCurrent: isCurrent)
            VStack(alignment: .leading, spacing: 2) {
                Text(parcel.address.streetLine)
                    .strikethrough(entry.status != .pending, color: .secondary)
                Text("\(parcel.address.postalCode) \(parcel.address.city)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if entry.status == .notDelivered {
                    Text("Niedoręczona")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(entry.status == .pending ? .primary : .secondary)
            Spacer()
            if entry.status == .pending {
                Button("Nawiguj", systemImage: "arrow.triangle.turn.up.right.circle.fill") { onNavigate(parcel) }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless)
            }
        }
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Przystanek \(entry.number), \(parcel.address.singleLine), \(entry.status.title)")
    }
}

/// Akcja przycisku nawigacji na karcie przystanku.
struct StopNavigation {
    let title: String
    /// Wyjaśnienie pod kartą, np. ile przystanków trafi do nawigacji.
    var hint: String?
    let action: () -> Void

    static func single(_ action: @escaping () -> Void) -> StopNavigation {
        StopNavigation(title: "Nawiguj", action: action)
    }
}

/// Karta przystanku z akcjami: nawigacja i oznaczenie doręczenia.
struct StopActionCard: View {
    let entry: RouteProgress.Entry
    let parcel: Parcel
    let isCurrent: Bool
    let navigation: StopNavigation
    let onSetStatus: (DeliveryStatus, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StopNumberBadge(entry: entry, isCurrent: isCurrent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parcel.address.streetLine)
                        .font(.headline)
                    Text("\(parcel.address.postalCode) \(parcel.address.city)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if entry.status != .pending {
                        Text(entry.status.title)
                            .font(.caption)
                            .foregroundStyle(entry.status == .delivered ? .green : .orange)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Button(action: navigation.action) {
                Label(navigation.title, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                if entry.status == .pending {
                    Button { onSetStatus(.delivered, entry.parcelID) } label: {
                        Label("Doręczona", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                    Button { onSetStatus(.notDelivered, entry.parcelID) } label: {
                        Label("Niedoręczona", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .tint(.orange)
                } else {
                    Button { onSetStatus(.pending, entry.parcelID) } label: {
                        Label("Cofnij oznaczenie", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }
}

/// Numer przystanku w kółku, kolor według statusu.
struct StopNumberBadge: View {
    let entry: RouteProgress.Entry
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Circle().fill(entry.status.color(isCurrent: isCurrent))
            switch entry.status {
            case .pending:
                Text("\(entry.number)").font(.subheadline.bold()).monospacedDigit()
            case .delivered:
                Image(systemName: "checkmark").font(.subheadline.bold())
            case .notDelivered:
                Image(systemName: "xmark").font(.subheadline.bold())
            }
        }
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

private struct StatusMenuItems: View {
    let entry: RouteProgress.Entry
    let onSetStatus: (DeliveryStatus, UUID) -> Void

    var body: some View {
        ForEach(DeliveryStatus.allCases, id: \.self) { status in
            if status != entry.status {
                Button(status.actionTitle) { onSetStatus(status, entry.parcelID) }
            }
        }
    }
}

extension DeliveryStatus {
    var title: String {
        switch self {
        case .pending: "Do doręczenia"
        case .delivered: "Doręczona"
        case .notDelivered: "Niedoręczona"
        }
    }

    var actionTitle: String {
        switch self {
        case .pending: "Cofnij oznaczenie"
        case .delivered: "Oznacz jako doręczoną"
        case .notDelivered: "Oznacz jako niedoręczoną"
        }
    }

    func color(isCurrent: Bool) -> Color {
        switch self {
        case .pending: isCurrent ? .accentColor : .gray
        case .delivered: .green
        case .notDelivered: .orange
        }
    }
}
