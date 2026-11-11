// Generuje obrazy PNG fikcyjnych listów przewozowych do ręcznych testów w symulatorze.
// Wszystkie dane są zmyślone.
//
// Użycie (z katalogu głównego repozytorium):
//   swift Tools/make-sample-labels.swift
//   xcrun simctl addmedia booted SampleLabels/*.png
import AppKit

struct Block {
    let x: CGFloat
    let y: CGFloat
    let fontSize: CGFloat
    let lines: [String]
}

struct SampleLabel {
    let name: String
    let blocks: [Block]
    /// Lekki obrót imituje zdjęcie zrobione z ręki.
    var rotation: CGFloat = 0
}

let labels = [
    SampleLabel(name: "01-jedna-kolumna", blocks: [
        Block(x: 80, y: 80, fontSize: 34, lines: ["NADAWCA:", "Sklep Internetowy Testowy Sp. z o.o.", "ul. Magazynowa 5", "02-652 Warszawa"]),
        Block(x: 80, y: 520, fontSize: 52, lines: ["ODBIORCA:", "Jan Kowalski", "ul. Długa 12/4", "31-019 Kraków", "tel. 600 100 200"]),
        Block(x: 80, y: 1250, fontSize: 30, lines: ["Waga: 2,5 kg", "Nr przesyłki: 620012345678901234"]),
    ]),
    SampleLabel(name: "02-dwie-kolumny", blocks: [
        Block(x: 80, y: 60, fontSize: 44, lines: ["KURIER TESTOWY EXPRESS"]),
        Block(x: 80, y: 220, fontSize: 30, lines: ["Od:", "Firma Testowa S.A.", "ul. Przemysłowa 3", "60-001 Poznań"]),
        Block(x: 780, y: 220, fontSize: 40, lines: ["Do:", "Katarzyna Wójcik", "al. Jana Pawła II 45A m. 12", "00-828 Warszawa"]),
    ], rotation: 2),
    SampleLabel(name: "03-ship-to", blocks: [
        Block(x: 80, y: 80, fontSize: 30, lines: ["6200 1234 5678 9012"]),
        Block(x: 80, y: 200, fontSize: 30, lines: ["FROM:", "Test Shop Ltd", "Portowa 1", "81-001 Gdynia"]),
        Block(x: 80, y: 650, fontSize: 50, lines: ["SHIP TO:", "Marek Zieliński", "Kwiatowa 7 lok. 3", "80-001 Gdańsk"]),
    ], rotation: -3),
    SampleLabel(name: "04-bez-kotwic", blocks: [
        Block(x: 100, y: 120, fontSize: 28, lines: ["Sklep Mały", "ul. Krótka 1", "50-001 Wrocław"]),
        Block(x: 100, y: 600, fontSize: 56, lines: ["Barbara Kaczmarek", "ul. Leśna 5", "40-001 Katowice"]),
    ]),
]

let size = NSSize(width: 1500, height: 2000)
let outputDirectory = URL(fileURLWithPath: "SampleLabels", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for label in labels {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(white: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    let transform = NSAffineTransform()
    transform.translateX(by: size.width / 2, yBy: size.height / 2)
    transform.rotate(byDegrees: label.rotation)
    transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
    transform.concat()

    for block in label.blocks {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: block.fontSize, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        for (index, line) in block.lines.enumerated() {
            // AppKit liczy Y od dołu — przeliczamy z układu „od góry”.
            let top = block.y + CGFloat(index) * block.fontSize * 1.35
            (line as NSString).draw(at: NSPoint(x: block.x, y: size.height - top - block.fontSize), withAttributes: attributes)
        }
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { fatalError("Nie udało się zapisać \(label.name)") }
    let url = outputDirectory.appendingPathComponent("\(label.name).png")
    try png.write(to: url)
    print("Zapisano \(url.path)")
}
