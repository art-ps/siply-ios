import SwiftUI
import UIKit

/// Обложка трека или папки; нет данных — заглушка с нотой.
struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

    // Декодируем один раз на Data: в списке одна обложка альбома повторяется у каждого трека
    private static let cache = NSCache<NSData, UIImage>()

    init(data: Data?, size: CGFloat) {
        self.data = data
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color(.secondarySystemFill))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 50 ? 8 : 4))
    }

    private var image: UIImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let cached = Self.cache.object(forKey: key) { return cached }
        guard let decoded = UIImage(data: data) else { return nil }
        Self.cache.setObject(decoded, forKey: key)
        return decoded
    }
}
