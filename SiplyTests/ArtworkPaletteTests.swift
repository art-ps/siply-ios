import XCTest
import SwiftUI
@testable import Siply

final class ArtworkPaletteTests: XCTestCase {
    private func png(_ color: UIColor, size: CGFloat = 8) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).pngData { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }
    private func hsb(_ c: Color) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return (h, s, b)
    }
    private let accentHue: CGFloat = {
        var h: CGFloat = 0
        UIColor(ArtworkPalette.accent).getHue(&h, saturation: nil, brightness: nil, alpha: nil)
        return h
    }()

    func testSolidRedArtworkKeepsHueDarkensBrightness() {
        let colors = ArtworkPalette.colors(from: png(.red))
        XCTAssertEqual(colors.count, 9)
        for c in colors {
            let v = hsb(c)
            XCTAssertTrue(v.h < 0.02 || v.h > 0.98, "hue \(v.h)")
            XCTAssertGreaterThanOrEqual(v.s, 0.35)
            XCTAssertTrue((0.18...0.45).contains(v.b), "brightness \(v.b)")
        }
    }

    func testNilArtworkAccentPalette() {
        let colors = ArtworkPalette.colors(from: nil)
        XCTAssertEqual(colors.count, 9)
        for c in colors {
            let v = hsb(c)
            XCTAssertEqual(v.h, accentHue, accuracy: 0.041)
            XCTAssertTrue((0.199...0.401).contains(v.b), "brightness \(v.b)")
        }
    }

    func testGarbageDataSameAsNil() {
        XCTAssertEqual(ArtworkPalette.colors(from: Data([1, 2, 3])), ArtworkPalette.colors(from: nil))
    }

    func testTinyArtworkStillNineColors() {
        XCTAssertEqual(ArtworkPalette.colors(from: png(.blue, size: 1)).count, 9)
    }

    func testSameInputSameOutput() {
        let data = png(.green)
        XCTAssertEqual(ArtworkPalette.colors(from: data), ArtworkPalette.colors(from: data))
    }
}
