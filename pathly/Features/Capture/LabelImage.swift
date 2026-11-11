import UIKit

/// Przygotowanie zdjęcia etykiety do OCR.
enum LabelImage {
    /// Dłuższy bok obrazu przekazywanego do Vision. Zdjęcie z aparatu ma ~12 Mpx;
    /// tekst etykiety jest czytelny w dużo mniejszej rozdzielczości, a OCR działa szybciej.
    static let maxDimension: CGFloat = 2400

    /// Pomniejsza zdjęcie i „wypala” jego orientację, aby Vision dostał obraz `.up`.
    static func prepareForRecognition(_ image: UIImage) -> CGImage? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
