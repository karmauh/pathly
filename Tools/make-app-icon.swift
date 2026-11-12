// Generuje ikonę aplikacji (1024 × 1024) w trzech wariantach: jasnym, ciemnym
// i barwionym (iOS 18+). Motyw: trasa z ponumerowanymi przystankami między
// bazą a ostatnim punktem.
//
// Użycie (z katalogu głównego repozytorium):
//   swift Tools/make-app-icon.swift
import AppKit

let size: CGFloat = 1024
let output = "pathly/Assets.xcassets/AppIcon.appiconset"

enum Variant: String, CaseIterable {
    case light = "AppIcon"
    case dark = "AppIcon-dark"
    case tinted = "AppIcon-tinted"
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Punkty trasy w kształcie litery S: od bazy (lewy dół) do celu (prawa góra).
/// Układ współrzędnych CoreGraphics: oś Y rośnie w górę.
let stops: [CGPoint] = [
    CGPoint(x: 250, y: 230),
    CGPoint(x: 560, y: 220),
    CGPoint(x: 780, y: 390),
    CGPoint(x: 500, y: 540),
    CGPoint(x: 720, y: 650),
]

func draw(_ variant: Variant, in context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Tło: gradient (jasny i ciemny) albo przezroczyste (barwiony — iOS nakłada kolor).
    switch variant {
    case .light, .dark:
        let colors = variant == .light
            ? [color(0x1E6BFF), color(0x12B5A6)]
            : [color(0x0B1E47), color(0x0A4A45)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    case .tinted:
        context.setFillColor(color(0x000000))
        context.fill(rect)
    }

    let ink = variant == .tinted ? color(0xFFFFFF) : color(0xFFFFFF)
    let accent = variant == .tinted ? color(0xFFFFFF, alpha: 0.75) : color(0xFFC83D)

    // Linia trasy: gładka krzywa przez wszystkie przystanki.
    let path = CGMutablePath()
    path.move(to: stops[0])
    for index in 1..<stops.count {
        let previous = stops[index - 1]
        let current = stops[index]
        let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
        path.addQuadCurve(to: mid, control: previous)
        if index == stops.count - 1 { path.addQuadCurve(to: current, control: mid) }
    }
    context.addPath(path)
    context.setStrokeColor(ink.copy(alpha: 0.9)!)
    context.setLineWidth(34)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineDash(phase: 0, lengths: [70, 46])
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])

    // Przystanki pośrednie: białe kropki.
    for stop in stops.dropFirst().dropLast() {
        context.setFillColor(ink)
        context.fillEllipse(in: CGRect(x: stop.x - 46, y: stop.y - 46, width: 92, height: 92))
    }

    // Baza: kwadrat z „dachem” na początku trasy.
    let base = stops[0]
    context.setFillColor(ink)
    context.fill(CGRect(x: base.x - 70, y: base.y - 80, width: 140, height: 110))
    let roof = CGMutablePath()
    roof.move(to: CGPoint(x: base.x - 100, y: base.y + 20))
    roof.addLine(to: CGPoint(x: base.x, y: base.y + 110))
    roof.addLine(to: CGPoint(x: base.x + 100, y: base.y + 20))
    roof.closeSubpath()
    context.addPath(roof)
    context.fillPath()

    // Cel: pinezka w kolorze akcentu.
    let pin = stops[stops.count - 1]
    let head = CGRect(x: pin.x - 95, y: pin.y + 20, width: 190, height: 190)
    let marker = CGMutablePath()
    marker.addEllipse(in: head)
    marker.move(to: CGPoint(x: pin.x - 78, y: pin.y + 80))
    marker.addLine(to: CGPoint(x: pin.x, y: pin.y - 60))
    marker.addLine(to: CGPoint(x: pin.x + 78, y: pin.y + 80))
    marker.closeSubpath()
    context.addPath(marker)
    context.setFillColor(accent)
    context.fillPath()
    let holeColor = variant == .tinted ? color(0x000000) : (variant == .light ? color(0x1593C8) : color(0x0B3346))
    context.setFillColor(holeColor)
    context.fillEllipse(in: head.insetBy(dx: 58, dy: 58))
}

for variant in Variant.allCases {
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    draw(variant, in: context)
    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    let url = URL(fileURLWithPath: "\(output)/\(variant.rawValue).png")
    try! image.representation(using: .png, properties: [:])!.write(to: url)
    print("Zapisano \(url.path)")
}
