import MapKit
import SwiftUI

/// Ręczne wskazanie położenia przesyłki, gdy geokoder nie znalazł adresu.
///
/// Kurier dotyka mapy w miejscu budynku; pinezkę można przestawiać kolejnym
/// dotknięciem. Mapa startuje od znanego punktu (kandydat geokodera albo baza).
struct LocationPickerView: View {
    let address: Address
    let onPick: (Coordinate) -> Void

    @State private var position: MapCameraPosition
    @State private var picked: Coordinate?
    @Environment(\.dismiss) private var dismiss

    /// - Parameter start: punkt startowy mapy; `nil` — cała Polska.
    init(address: Address, start: Coordinate?, onPick: @escaping (Coordinate) -> Void) {
        self.address = address
        self.onPick = onPick
        let region = start.map {
            MKCoordinateRegion(center: $0.clLocationCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        } ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.0, longitude: 19.4),
            span: MKCoordinateSpan(latitudeDelta: 6.5, longitudeDelta: 10.5)
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let picked {
                    Marker(address.streetLine, systemImage: "shippingbox.fill", coordinate: picked.clLocationCoordinate)
                        .tint(.orange)
                }
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    picked = Coordinate(coordinate)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(address.singleLine)
                    .font(.headline)
                Text(picked == nil
                     ? "Dotknij mapy w miejscu budynku."
                     : "Dotknij ponownie, aby przestawić pinezkę.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.bar)
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Wskaż miejsce")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Anuluj", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ustaw") {
                    if let picked {
                        onPick(picked)
                        dismiss()
                    }
                }
                .disabled(picked == nil)
            }
        }
    }
}
