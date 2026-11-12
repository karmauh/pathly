import MapKit
import SwiftUI

/// Mapa trasy: baza, ponumerowane przystanki i linia w kolejności doręczeń.
///
/// Linia łączy przystanki odcinkami prostymi — macierz czasów przejazdu nie
/// zawiera geometrii dróg, a pobieranie jej dla każdego odcinka zużywałoby
/// limity usługi. Dokładną drogę do przystanku pokazuje nawigacja.
struct RouteMapView: View {
    let progress: RouteProgress
    let parcels: [UUID: Parcel]
    let base: Coordinate?
    let onSetStatus: (DeliveryStatus, UUID) -> Void
    let onNavigate: (Parcel) -> Void

    @State private var selection: UUID?
    @State private var position: MapCameraPosition = .automatic

    /// Wybrany znacznik, a bez wyboru — następny przystanek.
    private var shownEntry: RouteProgress.Entry? {
        progress.entries.first { $0.id == selection } ?? progress.current
    }

    private var lineCoordinates: [CLLocationCoordinate2D] {
        let stops = progress.entries.compactMap { parcels[$0.parcelID]?.coordinate }
        let route = base.map { [$0] + stops + [$0] } ?? stops
        return route.map(\.clLocationCoordinate)
    }

    var body: some View {
        Map(position: $position, selection: $selection) {
            MapPolyline(coordinates: lineCoordinates)
                .stroke(.blue.opacity(0.6), lineWidth: 3)

            if let base {
                Marker("Baza", systemImage: "house.fill", coordinate: base.clLocationCoordinate)
                    .tint(.indigo)
            }

            ForEach(progress.entries) { entry in
                if let parcel = parcels[entry.parcelID], let coordinate = parcel.coordinate {
                    Marker(parcel.address.streetLine, monogram: Text("\(entry.number)"), coordinate: coordinate.clLocationCoordinate)
                        .tint(entry.status.color(isCurrent: entry.id == progress.current?.id))
                        .tag(entry.parcelID)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            if let entry = shownEntry, let parcel = parcels[entry.parcelID] {
                StopActionCard(
                    entry: entry,
                    parcel: parcel,
                    isCurrent: entry.id == progress.current?.id,
                    onSetStatus: { status, id in
                        onSetStatus(status, id)
                        // Po oznaczeniu karta przechodzi do następnego przystanku.
                        selection = nil
                    },
                    onNavigate: onNavigate
                )
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
    }
}
