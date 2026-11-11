import Foundation

/// Zlecanie geokodowania przesyłki. View modele zależą od tego protokołu,
/// a nie od konkretnej kolejki — w testach wystarczy prosta atrapa.
protocol GeocodingScheduling {
    func enqueue(_ parcelID: UUID)
}
