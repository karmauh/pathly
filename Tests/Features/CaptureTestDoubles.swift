import CoreGraphics
import Foundation
@testable import pathly

/// Atrapa OCR: zwraca zadane linie albo błąd.
struct MockTextRecognizer: TextRecognizer {
    enum Failure: Error { case recognitionFailed }
    let result: Result<[RecognizedLine], Failure>

    func recognizeLines(in image: CGImage) async throws -> [RecognizedLine] {
        try result.get()
    }
}

/// Magazyn przesyłek w pamięci.
@MainActor
final class InMemoryParcelStore: ParcelStore {
    private(set) var parcels: [UUID: Address] = [:]
    var statuses: [UUID: GeocodingStatus] = [:]
    var candidates: [UUID: [GeocodingCandidate]] = [:]
    private(set) var chosenLocations: [UUID: GeocodingCandidate] = [:]
    var shouldFail = false

    func addParcel(address: Address) throws -> UUID {
        if shouldFail { throw ParcelStoreError.parcelNotFound }
        let id = UUID()
        parcels[id] = address
        return id
    }

    func address(ofParcel id: UUID) throws -> Address? { parcels[id] }

    func updateAddress(ofParcel id: UUID, to address: Address) throws {
        guard parcels[id] != nil else { throw ParcelStoreError.parcelNotFound }
        parcels[id] = address
    }

    func deleteParcels(_ ids: Set<UUID>) throws {
        if shouldFail { throw ParcelStoreError.parcelNotFound }
        ids.forEach { parcels[$0] = nil }
    }

    func geocodingStatus(ofParcel id: UUID) throws -> GeocodingStatus? { statuses[id] }

    func geocodingCandidates(ofParcel id: UUID) throws -> [GeocodingCandidate] { candidates[id] ?? [] }

    func chooseLocation(_ candidate: GeocodingCandidate, forParcel id: UUID) throws {
        if shouldFail { throw ParcelStoreError.parcelNotFound }
        chosenLocations[id] = candidate
    }
}

/// Atrapa kolejki geokodowania: zapamiętuje zlecone przesyłki.
@MainActor
final class RecordingGeocodingScheduler: GeocodingScheduling {
    private(set) var enqueued: [UUID] = []
    func enqueue(_ parcelID: UUID) { enqueued.append(parcelID) }
}

/// Najmniejszy obraz — atrapa OCR i tak go nie czyta.
func makeBlankImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
