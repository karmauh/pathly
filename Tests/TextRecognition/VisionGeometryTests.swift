import Testing
@testable import pathly

@Suite("VisionGeometry")
struct VisionGeometryTests {
    @Test("Odwraca oś Y: dół obrazu w Vision to góra w parserze")
    func flipsYAxis() {
        // Linia przy górnej krawędzi zdjęcia: w Vision y ≈ 0.9 (liczone od dołu).
        let box = VisionGeometry.textBox(corners: [(0.1, 0.95), (0.5, 0.95), (0.5, 0.90), (0.1, 0.90)])
        #expect(abs(box.minX - 0.1) < 1e-9)
        #expect(abs(box.minY - 0.05) < 1e-9)
        #expect(abs(box.width - 0.4) < 1e-9)
        #expect(abs(box.height - 0.05) < 1e-9)
    }

    @Test("Lekko obrócona linia daje obejmujący prostokąt")
    func rotatedQuadrilateral() {
        let box = VisionGeometry.textBox(corners: [(0.1, 0.52), (0.5, 0.55), (0.5, 0.50), (0.1, 0.47)])
        #expect(abs(box.minY - 0.45) < 1e-9)
        #expect(abs(box.maxY - 0.53) < 1e-9)
    }
}
