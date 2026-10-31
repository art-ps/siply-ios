import SwiftUI
import UIKit

/// Палитра 3×3 для фона плеера: обложка сжимается до 9 пикселей.
enum ArtworkPalette {
    static let accent = Color(red: 0x6B / 255, green: 0x85 / 255, blue: 0xA3 / 255)

    /// Ровно 9 цветов, построчно. Нет обложки или она битая — палитра акцента.
    static func colors(from data: Data?) -> [Color] {
        guard let data, let cg = UIImage(data: data)?.cgImage else { return fallback }
        var buf = [UInt8](repeating: 0, count: 3 * 3 * 4)
        let drawn = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: 3, height: 3, bitsPerComponent: 8, bytesPerRow: 12,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 3, height: 3))
            return true
        }
        guard drawn else { return fallback }
        return (0..<9).map { i in
            let ui = UIColor(red: CGFloat(buf[i * 4]) / 255, green: CGFloat(buf[i * 4 + 1]) / 255,
                             blue: CGFloat(buf[i * 4 + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            ui.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            // Приглушаем: фон не должен спорить с текстом поверх.
            return Color(hue: h, saturation: max(s, 0.35), brightness: min(max(b, 0.18), 0.45))
        }
    }

    private static var fallback: [Color] {
        var h: CGFloat = 0, s: CGFloat = 0
        UIColor(accent).getHue(&h, saturation: &s, brightness: nil, alpha: nil)
        return (0..<9).map { i in
            let row = CGFloat(i / 3), col = CGFloat(i % 3)
            var hue = (h + (col - 1) * 0.04).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            return Color(hue: hue, saturation: s, brightness: 0.2 + row * 0.1)
        }
    }
}
